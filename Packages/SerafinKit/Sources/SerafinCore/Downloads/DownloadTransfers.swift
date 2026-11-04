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
///
/// A transfer started into a file replaces any before it there, so only the newest is heard: iOS can report a task
/// from an earlier launch after a new one has started into its file, as when Serafin was closed from the app switcher.
public final class DownloadTransfers: NSObject, URLSessionDownloadDelegate, Sendable {
    /// What happened to a transfer.
    public enum Event: Sendable, Equatable {
        /// Part of the file has arrived: `received` bytes of `expected`, when the server said how many.
        case progress(fileName: String, received: Int64, expected: Int64?)
        /// The whole file is saved in the media folder, `bytes` long.
        case finished(fileName: String, bytes: Int64)
        /// The transfer, the session's task `task`, stopped. The resume data, when there is any, carries on from
        /// where it stopped.
        case failed(fileName: String, failure: DownloadFailure, resumeData: Data?, task: Int)
        /// iOS stopped the transfer, the session's task `task`, because Serafin was closed from the app switcher,
        /// which stops all of Serafin's, and reports it once Serafin runs again. It can carry on from the resume
        /// data, when iOS kept what had arrived, or else start again at `url`, the address it had, using cellular
        /// data only when `allowsCellularAccess` says.
        case stoppedWhenClosed(fileName: String, resumeData: Data?, url: URL?, allowsCellularAccess: Bool, task: Int)
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
    /// The session's task for each file a transfer has started into this launch, by file name: the one whose
    /// reports count.
    private let current = Mutex<[String: Int]>([:])

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

    /// Starts downloading `request` into the file named `fileName`, in place of any transfer into it before.
    ///
    /// - Returns: The session's task for the transfer.
    @discardableResult
    func start(_ request: URLRequest, fileName: String) -> Int? {
        guard let session = self.session.withLock({ $0 }) else { return nil }
        return run(session.downloadTask(with: request), into: fileName)
    }

    /// Carries on a transfer that stopped, from its resume data, in place of any transfer into its file since.
    ///
    /// - Returns: The session's task for the transfer.
    @discardableResult
    func resume(_ resumeData: Data, fileName: String) -> Int? {
        guard let session = self.session.withLock({ $0 }) else { return nil }
        return run(session.downloadTask(withResumeData: resumeData), into: fileName)
    }

    /// Whether what the session's task `task` reports for the file `fileName` counts: it's the newest transfer
    /// started into the file this launch, or none has started into it, as for one left running by an earlier launch.
    func isCurrent(_ task: Int, for fileName: String) -> Bool {
        current.withLock { current in current[fileName].map { $0 == task } ?? true }
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

    /// Runs `task` into the file `fileName`, as the transfer whose reports count from now on.
    private func run(_ task: URLSessionDownloadTask, into fileName: String) -> Int {
        task.taskDescription = fileName
        reported.withLock { $0[fileName] = 0 }
        _ = settled.withLock { $0.remove(fileName) }
        current.withLock { $0[fileName] = task.taskIdentifier }
        task.resume()
        return task.taskIdentifier
    }

    /// The file `task` brings, when what it reports counts.
    private func fileName(of task: URLSessionTask) -> String? {
        guard let fileName = task.taskDescription, isCurrent(task.taskIdentifier, for: fileName) else { return nil }
        return fileName
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
        guard isCurrent(downloadTask.taskIdentifier, for: fileName) else {
            // Replaced by a newer transfer into the same file, so nothing it brings would be kept.
            downloadTask.cancel()
            return
        }
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
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let fileName = fileName(of: downloadTask) else { return }
        // What had arrived before the transfer stopped shows at once.
        reported.withLock { $0[fileName] = fileOffset }
        let expected = expectedTotalBytes > 0 ? expectedTotalBytes : nil
        continuation.yield(.progress(fileName: fileName, received: fileOffset, expected: expected))
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let fileName = fileName(of: downloadTask), Self.isPlainFileName(fileName) else { return }
        let task = downloadTask.taskIdentifier
        settled.withLock { _ = $0.insert(fileName) }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        // 206 when a stopped transfer carried on from its resume data.
        guard status == 200 || status == 206 else {
            Self.logger.error("A download was refused with status \(status ?? 0, privacy: .public)")
            continuation.yield(
                .failed(fileName: fileName, failure: Self.failure(forStatus: status), resumeData: nil, task: task))
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
            continuation.yield(
                .failed(fileName: fileName, failure: Self.failure(for: error), resumeData: nil, task: task))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let fileName = fileName(of: task) else { return }
        reported.withLock { $0[fileName] = nil }
        let wasSettled = settled.withLock { $0.remove(fileName) != nil }
        guard !wasSettled else { return }
        continuation.yield(
            Self.stop(of: task.taskIdentifier, into: fileName, request: task.originalRequest, error: error))
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

    /// What the session's task `task` into the file `fileName`, sent as `request`, ending with `error` and no saved
    /// file means. iOS stops every transfer of Serafin's when Serafin is closed from the app switcher, and reports each
    /// with its resume data, when it kept what had arrived, once Serafin runs again: such a transfer can carry on.
    static func stop(of task: Int, into fileName: String, request: URLRequest?, error: (any Error)?) -> Event {
        guard let error else {
            // Ended with neither a file nor an error.
            return .failed(fileName: fileName, failure: .serverError, resumeData: nil, task: task)
        }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if (error as? URLError)?.backgroundTaskCancelledReason == .userForceQuitApplication {
            return .stoppedWhenClosed(
                fileName: fileName,
                resumeData: resumeData,
                url: request?.url,
                allowsCellularAccess: request?.allowsCellularAccess ?? false,
                task: task
            )
        }
        return .failed(fileName: fileName, failure: failure(for: error), resumeData: resumeData, task: task)
    }

    /// The failure an HTTP status means for a download.
    static func failure(forStatus status: Int?) -> DownloadFailure {
        switch status {
        case 401, 403: .notAllowed
        case 404: .notFound
        default: .serverError
        }
    }

    /// The failure an error from the transfer or from saving the file means. A transfer iOS stopped in the background,
    /// as when Serafin was closed or Background App Refresh is off, was interrupted.
    static func failure(for error: any Error) -> DownloadFailure {
        if (error as? URLError)?.backgroundTaskCancelledReason != nil {
            return .interrupted
        }
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
