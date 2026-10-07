import AVFoundation
import SerafinCore

/// Answers AVFoundation's certificate challenges with the user's pins, so a server with a pinned self-signed
/// certificate streams like any other.
///
/// AVPlayer does its own networking and never sees Serafin's URLSession delegate. It asks the asset's resource
/// loader delegate instead, which this is.
final class PinnedStreamLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    /// The queue AVFoundation calls the loader on.
    static let queue = DispatchQueue(label: "app.getserafin.serafin.stream-loader")

    private let pinning: PinningDelegate?

    init(pinning: PinningDelegate?) {
        self.pinning = pinning
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge
    ) -> Bool {
        guard let pinning else { return false }
        let (disposition, credential) = pinning.answer(to: authenticationChallenge)
        switch disposition {
        case .useCredential:
            guard let credential else { return false }
            authenticationChallenge.sender?.use(credential, for: authenticationChallenge)
            return true
        case .cancelAuthenticationChallenge:
            authenticationChallenge.sender?.cancel(authenticationChallenge)
            return true
        default:
            // The system's own handling, for a certificate it trusts.
            return false
        }
    }
}
