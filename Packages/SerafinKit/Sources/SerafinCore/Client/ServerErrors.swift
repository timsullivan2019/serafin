import Foundation

/// Turns the errors from requests to a server into ``SerafinError``s.
struct ServerErrors: Sendable {
    /// The delegate that knows which certificates it refused.
    let pinning: PinningDelegate

    /// The ``SerafinError`` for `error` from a request to `url`, or the cancellation, passed on.
    ///
    /// - Parameter statuses: What particular HTTP statuses mean for this request. Any other status is an
    ///   ``SerafinError/unexpectedResponse(status:)``.
    func translate(_ error: any Error, from url: URL, statuses: [Int: SerafinError] = [:]) -> any Error {
        switch error {
        case is SerafinError, is CancellationError:
            return error
        case let error as URLError:
            if Task.isCancelled {
                return CancellationError()
            }
            if error.isCertificateFailure, let host = url.host(), let presented = pinning.rejectedCertificate(for: host)
            {
                return SerafinError.untrustedCertificate(presented)
            }
            return SerafinError.serverUnreachable
        default:
            if let status = HTTPStatus.of(error) {
                return statuses[status] ?? SerafinError.unexpectedResponse(status: status)
            }
            return SerafinError.unexpectedResponse(status: nil)
        }
    }
}
