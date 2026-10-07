import Foundation
import Observation
import SwiftUI

#if canImport(LocalAuthentication)
    import LocalAuthentication
#endif

/// Serafin's optional lock, off until the owner turns it on in Settings.
///
/// When it's on, Serafin opens locked, and locks again once it has been in the background for the grace period the
/// owner chose. Face ID, Touch ID or Optic ID unlocks it, with the device passcode as the fallback, so nobody is ever
/// locked out of their own library. Time in the background is measured on a clock that changing the device's time
/// can't wind back. A device without a passcode can't confirm its owner, so the lock steps aside there.
@Observable @MainActor public final class AppLock {
    /// The settings' keys in user defaults. Neither is a secret: the lock guards the app, and the Keychain guards the
    /// tokens.
    static let enabledKey = "appLock.enabled"
    static let graceKey = "appLock.grace"

    /// Whether the lock is on.
    public private(set) var isEnabled: Bool
    /// How long Serafin may sit in the background before it locks again.
    private(set) var grace: LockGrace
    /// Whether Serafin is locked now.
    private(set) var isLocked: Bool
    /// Whether the owner is being asked to confirm, so a second request waits.
    private(set) var isConfirming = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let owner: any OwnerConfirmation
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant
    /// When the app went to the background, or nil while it's in use.
    private var backgroundedAt: ContinuousClock.Instant?

    /// The lock the app runs with, its settings in the standard user defaults.
    public convenience init() {
        self.init(defaults: .standard, owner: DeviceOwner(), now: { ContinuousClock.now })
    }

    init(
        defaults: UserDefaults,
        owner: any OwnerConfirmation,
        now: @escaping @MainActor () -> ContinuousClock.Instant
    ) {
        let enabled = defaults.bool(forKey: Self.enabledKey)
        self.defaults = defaults
        self.owner = owner
        self.now = now
        isEnabled = enabled
        grace = LockGrace(rawValue: defaults.integer(forKey: Self.graceKey)) ?? .immediately
        isLocked = enabled && owner.check != .unavailable
    }

    /// How this device confirms its owner, which names the setting.
    var check: OwnerCheck {
        owner.check
    }

    /// Whether something asked for from outside the app, such as by Siri, can go ahead: the lock is off, or the owner
    /// has unlocked Serafin since it was last in the background. On the way back from the background the app hasn't
    /// yet decided whether to lock, so a request waits until it has.
    public var isOpen: Bool {
        !isLocked && !(isEnabled && backgroundedAt != nil)
    }

    /// Follows the app in and out of the background, locking it on its return once the grace period has passed.
    ///
    /// - Parameter phase: The app's phase across all its windows, so one window going to the background while
    ///   another stays in use doesn't lock either.
    public func appMoved(to phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = backgroundedAt ?? now()
        case .active:
            if let since = backgroundedAt, isEnabled, owner.check != .unavailable, now() - since >= grace.duration {
                isLocked = true
            }
            backgroundedAt = nil
            if owner.check == .unavailable {
                isLocked = false
            }
        default:
            break
        }
    }

    /// Asks the owner to unlock Serafin.
    func unlock() async {
        guard isLocked, !isConfirming else { return }
        if await confirm(String(localized: "Unlock Serafin", bundle: .module, comment: "Reason the lock asks.")) {
            isLocked = false
        }
    }

    /// Turns the lock on or off, once the owner confirms, so a borrowed, unlocked phone can't change it.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, !isConfirming else { return }
        let reason =
            enabled
            ? String(localized: "Turn on the lock", bundle: .module, comment: "Reason the lock asks when turned on.")
            : String(localized: "Turn off the lock", bundle: .module, comment: "Reason the lock asks when turned off.")
        guard await confirm(reason) else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    /// Sets how long Serafin may sit in the background before it locks again.
    func setGrace(_ grace: LockGrace) {
        self.grace = grace
        defaults.set(grace.rawValue, forKey: Self.graceKey)
    }

    private func confirm(_ reason: String) async -> Bool {
        isConfirming = true
        defer { isConfirming = false }
        return await owner.confirm(reason: reason)
    }
}

/// How long Serafin may sit in the background before it locks again, as iOS offers for its own passcode.
enum LockGrace: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600

    var id: Int { rawValue }

    /// The grace period as a length of time.
    var duration: Duration { .seconds(rawValue) }

    /// The choice as Settings lists it.
    var title: String {
        switch self {
        case .immediately:
            String(localized: "Immediately", bundle: .module, comment: "Lock grace period: no grace.")
        case .oneMinute:
            String(localized: "After 1 Minute", bundle: .module, comment: "Lock grace period.")
        case .fiveMinutes:
            String(localized: "After 5 Minutes", bundle: .module, comment: "Lock grace period.")
        case .fifteenMinutes:
            String(localized: "After 15 Minutes", bundle: .module, comment: "Lock grace period.")
        case .oneHour:
            String(localized: "After 1 Hour", bundle: .module, comment: "Lock grace period.")
        }
    }
}

/// How a device confirms its owner.
enum OwnerCheck: Sendable {
    case faceID, touchID, opticID, passcode
    /// No passcode is set, so nothing can confirm the owner.
    case unavailable
}

/// Asks the device to confirm its owner is holding it.
protocol OwnerConfirmation: Sendable {
    /// How the device confirms its owner.
    var check: OwnerCheck { get }
    /// Asks the owner to confirm, and says whether they did.
    func confirm(reason: String) async -> Bool
}

/// The device's own Face ID, Touch ID or Optic ID, with the passcode as the fallback.
private struct DeviceOwner: OwnerConfirmation {
    var check: OwnerCheck {
        #if canImport(LocalAuthentication)
            let context = LAContext()
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
            // Asking about biometrics fills in which kind the device has.
            _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: return .passcode
            }
        #else
            return .unavailable
        #endif
    }

    func confirm(reason: String) async -> Bool {
        #if canImport(LocalAuthentication)
            (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        #else
            false
        #endif
    }
}
