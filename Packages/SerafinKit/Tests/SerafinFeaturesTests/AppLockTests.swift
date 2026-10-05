import Foundation
import SwiftUI
import Testing

@testable import SerafinFeatures

/// An owner who answers each request as told, on a device with the given check.
private final class FakeOwner: OwnerConfirmation, @unchecked Sendable {
    var check: OwnerCheck
    var answers: [Bool]
    private(set) var reasons: [String] = []

    init(check: OwnerCheck = .faceID, answers: [Bool] = []) {
        self.check = check
        self.answers = answers
    }

    func confirm(reason: String) async -> Bool {
        reasons.append(reason)
        return answers.isEmpty ? false : answers.removeFirst()
    }
}

/// A clock the test moves by hand.
@MainActor private final class FakeClock {
    var now = ContinuousClock.now
}

@MainActor
@Suite struct AppLockTests {
    private let defaults: UserDefaults
    private let clock = FakeClock()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "app.getserafin.serafin.tests.\(UUID().uuidString)"))
    }

    private func lock(_ owner: FakeOwner) -> AppLock {
        AppLock(defaults: defaults, owner: owner, now: { [clock] in clock.now })
    }

    @Test func itStartsOffAndOpen() {
        let lock = lock(FakeOwner())
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
        #expect(lock.grace == .immediately)
    }

    @Test func turningItOnNeedsTheOwnerAndLasts() async {
        let owner = FakeOwner(answers: [false, true])
        let lock = lock(owner)
        await lock.setEnabled(true)
        #expect(!lock.isEnabled)
        await lock.setEnabled(true)
        #expect(lock.isEnabled)
        #expect(owner.reasons.count == 2)
        // The next launch opens locked.
        #expect(self.lock(FakeOwner()).isLocked)
    }

    @Test func turningItOffNeedsTheOwnerToo() async {
        defaults.set(true, forKey: AppLock.enabledKey)
        let lock = lock(FakeOwner(answers: [false, true]))
        await lock.setEnabled(false)
        #expect(lock.isEnabled)
        await lock.setEnabled(false)
        #expect(!lock.isEnabled)
    }

    @Test func onlyTheOwnerUnlocksIt() async {
        defaults.set(true, forKey: AppLock.enabledKey)
        let lock = lock(FakeOwner(answers: [false, true]))
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(!lock.isLocked)
    }

    @Test func itLocksAgainOnceTheGracePeriodHasPassed() async {
        defaults.set(true, forKey: AppLock.enabledKey)
        let lock = lock(FakeOwner(answers: [true]))
        await lock.unlock()
        lock.setGrace(.oneMinute)

        lock.appMoved(to: .background)
        clock.now += .seconds(30)
        lock.appMoved(to: .active)
        #expect(!lock.isLocked)

        lock.appMoved(to: .background)
        clock.now += .seconds(61)
        lock.appMoved(to: .active)
        #expect(lock.isLocked)
    }

    @Test func immediatelyLocksOnEveryReturnButNotForAGlance() async {
        defaults.set(true, forKey: AppLock.enabledKey)
        let lock = lock(FakeOwner(answers: [true]))
        await lock.unlock()

        // Control Center or a notification only makes the app inactive.
        lock.appMoved(to: .inactive)
        lock.appMoved(to: .active)
        #expect(!lock.isLocked)

        lock.appMoved(to: .background)
        lock.appMoved(to: .active)
        #expect(lock.isLocked)
    }

    @Test func theGraceSettingLasts() {
        let lock = lock(FakeOwner())
        lock.setGrace(.fifteenMinutes)
        #expect(self.lock(FakeOwner()).grace == .fifteenMinutes)
    }

    @Test func withoutAPasscodeTheLockStepsAside() {
        defaults.set(true, forKey: AppLock.enabledKey)
        let owner = FakeOwner(check: .unavailable)
        let lock = lock(owner)
        #expect(!lock.isLocked)
        lock.appMoved(to: .background)
        lock.appMoved(to: .active)
        #expect(!lock.isLocked)
    }

    @Test func graceChoicesReadAsIOSWritesThem() {
        #expect(
            LockGrace.allCases.map(\.duration) == [.zero, .seconds(60), .seconds(300), .seconds(900), .seconds(3600)])
        #expect(LockGrace.immediately.title == "Immediately")
        #expect(LockGrace.fiveMinutes.title == "After 5 Minutes")
        #expect(OwnerCheck.faceID.settingTitle == "Require Face ID")
        #expect(OwnerCheck.touchID.unlockTitle == "Unlock with Touch ID")
    }
}
