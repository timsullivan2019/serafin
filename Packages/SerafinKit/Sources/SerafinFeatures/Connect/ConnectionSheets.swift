import SerafinCore
import SerafinDesign
import SwiftUI

/// The warning before Serafin connects to a server on the local network without encryption. It can't be swiped
/// away: the user picks Connect Anyway or Cancel.
struct UnencryptedConnectionSheet: View {
    let server: Server
    let accept: () -> Void
    let cancel: () -> Void

    var body: some View {
        WarningSheet(
            systemImage: "lock.open.trianglebadge.exclamationmark",
            title: String(
                localized: "This Connection Isn't Encrypted",
                bundle: .module,
                comment: "Title of the warning before connecting over plain HTTP."
            ),
            message: String(
                localized:
                    "\(server.name) uses HTTP, so your sign-in and what you watch cross your network unencrypted. Only connect on a network you trust, like your home Wi-Fi.",
                bundle: .module,
                comment: "Warning before connecting over plain HTTP. The argument is the server's name."
            ),
            acceptTitle: String(
                localized: "Connect Anyway", bundle: .module, comment: "Button that accepts the plain HTTP warning."),
            accept: accept,
            cancel: cancel
        )
    }
}

/// The certificate check before Serafin trusts a server whose certificate iOS doesn't. The user compares the
/// fingerprint with the one their server shows, then trusts it or cancels.
struct CertificateSheet: View {
    let fingerprint: CertificateFingerprint
    let host: String
    let trust: () -> Void
    let cancel: () -> Void

    var body: some View {
        WarningSheet(
            systemImage: "lock.trianglebadge.exclamationmark",
            title: String(
                localized: "Check This Server's Certificate",
                bundle: .module,
                comment: "Title of the certificate check."
            ),
            message: String(
                localized:
                    "iOS doesn't recognize the certificate for \(host). Compare this SHA-256 fingerprint with the one your server shows, and trust it only if they match.",
                bundle: .module,
                comment: "Explanation of the certificate check. The argument is the server's host name."
            ),
            acceptTitle: String(
                localized: "Trust This Certificate", bundle: .module, comment: "Button that pins a certificate."),
            accept: trust,
            cancel: cancel
        ) {
            Text(fingerprint.certificateSHA256)
                .font(.footnote.monospaced())
                .foregroundStyle(.textPrimary)
                .textSelection(.enabled)
                .padding(Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surface, in: .rounded(.small))
                .accessibilityLabel(
                    String(localized: "Fingerprint", bundle: .module, comment: "VoiceOver label of a fingerprint.")
                )
                .accessibilityValue(fingerprint.certificateSHA256)
        }
    }
}

/// A sheet that asks the user to accept a risk: a symbol, a title, an explanation, optional details, and two
/// buttons. It can't be swiped away.
private struct WarningSheet<Details: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let acceptTitle: String
    let accept: () -> Void
    let cancel: () -> Void
    @ViewBuilder let details: () -> Details

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.small) {
                    Text(title)
                        .typography(.title)
                        .foregroundStyle(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .typography(.body)
                        .foregroundStyle(.textSecondary)
                }
                .multilineTextAlignment(.center)
                details()
            }
            .padding(Spacing.large)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.small) {
                Button(action: cancel) {
                    Text(String(localized: "Cancel", bundle: .module, comment: "Button that backs out of a warning."))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button(role: .destructive, action: accept) {
                    Text(acceptTitle)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(Spacing.large)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }
}

extension WarningSheet where Details == EmptyView {
    init(
        systemImage: String,
        title: String,
        message: String,
        acceptTitle: String,
        accept: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            acceptTitle: acceptTitle,
            accept: accept,
            cancel: cancel
        ) { EmptyView() }
    }
}

#Preview("Unencrypted") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            UnencryptedConnectionSheet(
                server: Server(
                    id: "home", name: "Living Room", url: URL(string: "http://192.168.1.20:8096") ?? .temporaryDirectory
                ),
                accept: {},
                cancel: {}
            )
        }
}

#Preview("Certificate, dark") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            if let certificate = PreviewCertificate.fingerprint {
                CertificateSheet(fingerprint: certificate, host: "jellyfin.local", trust: {}, cancel: {})
            }
        }
        .preferredColorScheme(.dark)
}

#if DEBUG
    /// A throwaway self-signed certificate, for previewing the certificate check.
    private enum PreviewCertificate {
        static var fingerprint: CertificateFingerprint? {
            let der =
                "MIIBdTCCARygAwIBAgIBATAKBggqhkjOPQQDAjAZMRcwFQYDVQQDDA5qZWxseWZpbi5sb2NhbDAgFw0yNjEwMDQxNjI1MDdaGA8yMTI2MDkxMDE2"
                + "MjUwN1owGTEXMBUGA1UEAwwOamVsbHlmaW4ubG9jYWwwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASwFcg0c5cP2ZZBJ+6jQJ+YEVOYA70zRSni"
                + "YN1bInXP3CAbcePli9EDc+Wz9nL/ZXAB0x+eXRjTu/wpITA0Bk9Uo1MwUTAdBgNVHQ4EFgQURKKl8xfgUAlaVc5Ey4uKpzD76gYwHwYDVR0jBBgw"
                + "FoAURKKl8xfgUAlaVc5Ey4uKpzD76gYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiBop+aInPDjNVWcwDKdylYrOA+H7VHrddf9"
                + "O7QX3vKIoAIgG+PWfaDcYAbouCt2YpIh9Toh1qi/1btQHAMd8oHYl9U="
            guard
                let data = Data(base64Encoded: der),
                let certificate = SecCertificateCreateWithData(nil, data as CFData)
            else { return nil }
            return CertificateFingerprint(certificate: certificate)
        }
    }
#endif
