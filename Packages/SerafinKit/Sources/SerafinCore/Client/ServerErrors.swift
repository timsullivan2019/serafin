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
        if let urlError = error as? URLError, !Task.isCancelled, urlError.isCertificateFailure, let host = url.host(),
            let presented = pinning.rejectedCertificate(for: host)
        {
            return SerafinError.untrustedCertificate(presented)
        }
        return SerafinError.translating(error, statuses: statuses)
    }
}

extension SerafinError {
    /// The ``SerafinError`` for an error from a request the SDK sent, or the cancellation, passed on.
    ///
    /// A network failure is ``serverUnreachable``, an HTTP status is looked up in `statuses` and is otherwise an
    /// ``unexpectedResponse(status:)``, and anything else, such as an answer that doesn't decode, is an unexpected
    /// response.
    ///
    /// - Parameter statuses: What particular HTTP statuses mean for this request.
    public static func translating(_ error: any Error, statuses: [Int: SerafinError] = [:]) -> any Error {
        switch error {
        case is SerafinError, is CancellationError:
            return error
        case is URLError:
            return Task.isCancelled ? CancellationError() : SerafinError.serverUnreachable
        default:
            if let status = HTTPStatus.of(error) {
                return statuses[status] ?? SerafinError.unexpectedResponse(status: status)
            }
            return SerafinError.unexpectedResponse(status: nil)
        }
    }
}
