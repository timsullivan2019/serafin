import SerafinDesign
import SwiftUI

/// What covers Serafin while it's locked: a lock and one button, asking for Face ID straight away.
struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: Spacing.large) {
            LockSymbol()
            Text(String(localized: "Serafin Is Locked", bundle: .module, comment: "Title of the lock screen."))
                .typography(.title)
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
            Button {
                Task { await lock.unlock() }
            } label: {
                Label(lock.check.unlockTitle, systemImage: lock.check.systemImage)
                    .typography(.headline)
                    .padding(.horizontal, Spacing.small)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(lock.isConfirming)
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background)
        // Asks as soon as the lock shows, as banking apps do; the button is there if the owner cancels.
        .task { await lock.unlock() }
    }
}

/// What the app switcher shows while the lock is on, so a glance at it reveals nothing of the library.
struct PrivacyCover: View {
    var body: some View {
        LockSymbol()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.background)
            .accessibilityHidden(true)
    }
}

private struct LockSymbol: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(.textSecondary)
            .accessibilityHidden(true)
    }
}

extension OwnerCheck {
    /// The lock screen's button, such as "Unlock with Face ID".
    var unlockTitle: String {
        switch self {
        case .faceID: String(localized: "Unlock with Face ID", bundle: .module, comment: "Lock screen button.")
        case .touchID: String(localized: "Unlock with Touch ID", bundle: .module, comment: "Lock screen button.")
        case .opticID: String(localized: "Unlock with Optic ID", bundle: .module, comment: "Lock screen button.")
        case .passcode, .unavailable:
            String(localized: "Unlock with Passcode", bundle: .module, comment: "Lock screen button.")
        }
    }

    /// The setting's name, such as "Require Face ID".
    var settingTitle: String {
        switch self {
        case .faceID: String(localized: "Require Face ID", bundle: .module, comment: "Settings toggle for the lock.")
        case .touchID: String(localized: "Require Touch ID", bundle: .module, comment: "Settings toggle for the lock.")
        case .opticID: String(localized: "Require Optic ID", bundle: .module, comment: "Settings toggle for the lock.")
        case .passcode, .unavailable:
            String(localized: "Require Passcode", bundle: .module, comment: "Settings toggle for the lock.")
        }
    }

    /// The symbol for the check.
    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .unavailable: "lock.fill"
        }
    }
}

#Preview("Light") {
    LockScreen(lock: AppLock())
}

#Preview("Dark") {
    LockScreen(lock: AppLock())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    LockScreen(lock: AppLock())
        .dynamicTypeSize(.accessibility5)
}
