import Foundation
import Synchronization
import os

/// Moves download files from the server to the device in a background `URLSession`, so transfers go on while Serafin
/// is suspended or closed, and iOS relaunches Serafin to save each one that finishes.
///
/// Each transfer is named by the file it saves to, a download's ID and extension, which is all it carries besides its
/// request. A finished file is moved into the media folder before the delegate returns, as URLSession deletes it
/// afterwards. Certificate challenges are answered with the user's pins, so a pinned self-signed server downloads
/// like any other. What happens is reported through ``events``, which ``Downloads`` reads.
public final class DownloadTransfers: NSObject, URLSessionDownloadDelegate, Sendable {
    /// What happened to a transfer.
    public enum Event: Sendable, Equatable {
        /// Part of the file has arrived: `received` bytes of `expected`, when the server said how many.
        case progress(fileName: String, received: Int64, expected: Int64?)
        /// The whole file is saved in the media folder, `bytes` long.
        case finished(fileName: String, bytes: Int64)
        /// The transfer stopped. The resume data, when there is any, carries on from where it stopped.
        case failed(fileName: String, failure: DownloadFailure, resumeData: Data?)
    }

    /// The identifier of the app's background session, which iOS uses to hand back its events.
    public static let backgroundIdentifier = "app.getserafin.serafin.downloads"

    /// The background session for the app: launch events on, never left to the system's discretion.
    public static func backgroundConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return configuration
    }

    private static let logger = Logger(serafinCategory: "downloads")
    /// The completion handler iOS passed when it relaunched the app for this session's events, called once they've
    /// all been delivered.
    private static let backgroundCompletion = Mutex<BackgroundCompletion>(.waiting)

    /// Where the relaunch for background events is: waiting for both iOS's completion handler and the session's
    /// last event, which can come in either order.
    private enum BackgroundCompletion {
        case waiting
        case handlerReceived(@Sendable () -> Void)
        case eventsDelivered
    }
    /// The smallest step a progress event reports, so a fast transfer doesn't flood ``events``.
    static let progressStep: Int64 = 512 * 1024

    /// What happened to each transfer, in order.
    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let pinning: PinningDelegate?
    private let mediaDirectory: URL
    private let session = Mutex<URLSession?>(nil)
    /// The bytes last reported for each transfer.
    private let reported = Mutex<[String: Int64]>([:])
    /// The transfers already reported as finished or failed, whose completion then has nothing more to say.
    private let settled = Mutex<Set<String>>([])

    /// Creates the transfers and their session. Make one per session identifier: iOS allows only one session per
    /// background identifier in a process.
    ///
    /// - Parameters:
    ///   - configuration: The session's configuration, ``backgroundConfiguration()`` in the app. Tests pass one with
    ///     a stub protocol.
    ///   - pinning: The certificate pins to accept.
    ///   - mediaDirectory: Where finished files are moved.
    public init(configuration: URLSessionConfiguration, pinning: PinningDelegate?, mediaDirectory: URL) {
        let (events, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = events
        self.continuation = continuation
        self.pinning = pinning
        self.mediaDirectory = mediaDirectory
        super.init()
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session.withLock { $0 = session }
    }

    /// Calls `completion` once the session has delivered the events iOS relaunched the app for, which may already
    /// have happened. The app passes the completion handler from
    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public static func handleBackgroundEvents(completion: @escaping @Sendable () -> Void) {
        let delivered = backgroundCompletion.withLock { state in
            if case .eventsDelivered = state {
                state = .waiting
                return true
            }
            state = .handlerReceived(completion)
            return false
        }
        if delivered {
            completion()
        }
    }

    /// Waits until the session has delivered the events iOS relaunched the app for.
    public static func backgroundEventsDelivered() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            handleBackgroundEvents { continuation.resume() }
        }
    }

    /// Starts downloading `request` into the file named `fileName`.
    func start(_ request: URLRequest, fileName: String) {
        guard let session = self.session.withLock({ $0 }) else { return }
        prepare(fileName)
        let task = session.downloadTask(with: request)
        task.taskDescription = fileName
        task.resume()
    }

    /// Carries on a transfer that stopped, from its resume data.
    func resume(_ resumeData: Data, fileName: String) {
        guard let session = self.session.withLock({ $0 }) else { return }
        prepare(fileName)
        let task = session.downloadTask(withResumeData: resumeData)
        task.taskDescription = fileName
        task.resume()
    }

    /// Stops the transfer into `fileName`, if one is running.
    func cancel(fileName: String) async {
        for task in await tasks() where task.taskDescription == fileName {
            task.cancel()
        }
    }

    /// The files transfers are running for, including ones that started before this launch.
    func runningFileNames() async -> Set<String> {
        Set(await tasks().compactMap(\.taskDescription))
    }

    private func tasks() async -> [URLSessionTask] {
        guard let session = self.session.withLock({ $0 }) else { return [] }
        return await session.allTasks
    }

    private func prepare(_ fileName: String) {
        reported.withLock { $0[fileName] = 0 }
        _ = settled.withLock { $0.remove(fileName) }
    }

    /// Whether `fileName` is a plain file name, so a transfer can only ever save into the media folder.
    static func isPlainFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty && !fileName.hasPrefix(".") && !fileName.contains("/") && !fileName.contains("\\")
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let fileName = downloadTask.taskDescription else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let step = max(Self.progressStep, (expected ?? 0) / 100)
        let due = reported.withLock { reported in
            guard totalBytesWritten - (reported[fileName] ?? 0) >= step else { return false }
            reported[fileName] = totalBytesWritten
            return true
        }
        if due {
            continuation.yield(.progress(fileName: fileName, received: totalBytesWritten, expected: expected))
        }
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let fileName = downloadTask.taskDescription, Self.isPlainFileName(fileName) else { return }
        settled.withLock { _ = $0.insert(fileName) }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        // 206 when a stopped transfer carried on from its resume data.
        guard status == 200 || status == 206 else {
            Self.logger.error("A download was refused with status \(status ?? 0, privacy: .public)")
            continuation.yield(.failed(fileName: fileName, failure: Self.failure(forStatus: status), resumeData: nil))
            return
        }
        let destination = mediaDirectory.appending(path: fileName, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: DownloadStore.protection]
            )
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes(
                [.protectionKey: DownloadStore.protection], ofItemAtPath: destination.path(percentEncoded: false))
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            continuation.yield(.finished(fileName: fileName, bytes: size))
        } catch {
            Self.logger.error("Could not save a download: \(error.localizedDescription, privacy: .private)")
            continuation.yield(.failed(fileName: fileName, failure: Self.failure(for: error), resumeData: nil))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let fileName = task.taskDescription else { return }
        reported.withLock { $0[fileName] = nil }
        let wasSettled = settled.withLock { $0.remove(fileName) != nil }
        guard !wasSettled else { return }
        let resumeData = error.flatMap { ($0 as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data }
        let failure = error.map(Self.failure(for:)) ?? .serverError
        continuation.yield(.failed(fileName: fileName, failure: failure, resumeData: resumeData))
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let (disposition, credential) = pinning?.answer(to: challenge) ?? (.performDefaultHandling, nil)
        completionHandler(disposition, credential)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let (disposition, credential) = pinning?.answer(to: challenge) ?? (.performDefaultHandling, nil)
        completionHandler(disposition, credential)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = Self.backgroundCompletion.withLock { state -> (@Sendable () -> Void)? in
            if case .handlerReceived(let completion) = state {
                state = .waiting
                return completion
            }
            state = .eventsDelivered
            return nil
        }
        completion?()
    }

    // MARK: - Failures

    /// The failure an HTTP status means for a download.
    static func failure(forStatus status: Int?) -> DownloadFailure {
        switch status {
        case 401, 403: .notAllowed
        case 404: .notFound
        default: .serverError
        }
    }

    /// The failure an error from the transfer or from saving the file means.
    static func failure(for error: any Error) -> DownloadFailure {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
            return .storageFull
        }
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCannotWriteToFile {
            return .storageFull
        }
        return .network
    }
}
