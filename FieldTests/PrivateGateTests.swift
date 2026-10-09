import Foundation
import LocalAuthentication
import notify
import Testing
import UIKit
@testable import FieldKit
@testable import Field

/// The lock in the running app: the cover is up before the notification's
/// handlers return (so before UIKit's snapshot), the Face ID prompt's own
/// resign and return never lock again, and "wipe instead" wipes.
@Suite(.serialized)
@MainActor struct PrivateGateTests {
    let suite = "PrivateGateTests-\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    func clean() { defaults.removePersistentDomain(forName: suite) }

    /// A space with a page in it, entered.
    func gate(asked: @escaping () async -> Bool = { true }, canLock: Bool = true) -> (PrivateGate, PrivateSpace) {
        let space = PrivateSpace()
        space.open().current.load(URL(string: "https://example.com/")!)
        let gate = PrivateGate(space: space, defaults: defaults, authenticate: asked, canLock: { canLock })
        gate.entered()
        return (gate, space)
    }

    func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    @Test func coveredBeforeTheSnapshot() {
        defer { clean() }
        let (gate, _) = gate()
        #expect(gate.shade == .none)
        #expect(!gate.shadeShown)
        post(UIScene.willDeactivateNotification)
        // Up by the time posting returns, as UIKit's snapshot waits for that.
        #expect(gate.shade == .cover)
        #expect(gate.shadeShown)
        post(UIScene.didEnterBackgroundNotification)
        #expect(gate.shade == .locked)
        #expect(gate.shadeShown)
        post(UIScene.didActivateNotification)
        #expect(gate.shade == .locked)
        gate.left()
        #expect(!gate.shadeShown)
    }

    @Test func theSwitcherOnlyCovers() {
        defer { clean() }
        let (gate, _) = gate()
        post(UIScene.willDeactivateNotification)
        post(UIScene.didActivateNotification)
        #expect(gate.shade == .none)
        #expect(gate.lock.state == .open)
        gate.left()
    }

    /// The prompt resigns the app and hands it back while it asks.
    @Test func faceIDsOwnPromptNeverLocksAgain() async throws {
        defer { clean() }
        var asked = 0
        let (gate, _) = gate(asked: {
            asked += 1
            NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: nil)
            try? await Task.sleep(for: .milliseconds(50))
            NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
            return true
        })
        post(UIScene.willDeactivateNotification)
        post(UIScene.didEnterBackgroundNotification)
        post(UIScene.didActivateNotification)
        #expect(gate.shade == .locked)
        await gate.unlock()
        #expect(asked == 1)
        #expect(gate.lock.state == .open)
        #expect(gate.shade == .none)
        post(UIScene.didActivateNotification)
        #expect(asked == 1)
        gate.left()
    }

    @Test func aRefusedUnlockStaysLocked() async {
        defer { clean() }
        let (gate, _) = gate(asked: { false })
        post(UIScene.didEnterBackgroundNotification)
        post(UIScene.didActivateNotification)
        await gate.unlock()
        #expect(gate.shade == .locked)
        gate.left()
    }

    @Test func wipeInsteadOfLock() async throws {
        defer { clean() }
        defaults.set(PrivateLock.Away.wipe.rawValue, forKey: PrivateSettings.awayKey)
        let (gate, space) = gate()
        post(UIScene.didEnterBackgroundNotification)
        try await Task.sleep(for: .milliseconds(300))
        #expect(space.tabs == nil)
        #expect(gate.lock.state == .open)
        gate.left()
    }

    @Test func noPasscodeWipes() async throws {
        defer { clean() }
        let (gate, space) = gate(canLock: false)
        gate.left()
        try await Task.sleep(for: .milliseconds(300))
        #expect(space.tabs == nil)
    }

    @Test func recordingBlanksIt() {
        defer { clean() }
        let (gate, _) = gate()
        gate.captureChanged(true)
        #expect(gate.shade == .captured)
        #expect(gate.shadeShown)
        gate.captureChanged(false)
        #expect(!gate.shadeShown)
        gate.left()
    }

    @Test func anOldFaceIDAnswerCannotCompleteANewAttempt() async throws {
        defer { clean() }
        var answers: [CheckedContinuation<Bool, Never>] = []
        let (gate, _) = gate(asked: { await withCheckedContinuation { answers.append($0) } })
        post(UIScene.didEnterBackgroundNotification)
        post(UIScene.didActivateNotification)
        let first = Task { await gate.unlock() }
        while answers.count < 1 { await Task.yield() }
        gate.left()
        gate.entered()
        let second = Task { await gate.unlock() }
        while answers.count < 2 { await Task.yield() }
        answers[0].resume(returning: true)
        await first.value
        #expect(gate.lock.state == .unlocking)
        answers[1].resume(returning: false)
        await second.value
        #expect(gate.lock.state == .locked)
        gate.left()
    }

    /// Face ID on the simulator, with a face enrolled and matched through
    /// BiometricKit's notifications (as `simctl spawn … notifyutil` would).
    /// Needs NSFaceIDUsageDescription in the host app, so it's opt-in:
    /// TEST_RUNNER_FIELD_FACEID=1, with the key passed as a build setting.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIELD_FACEID"] != nil))
    func faceIDOnTheSimulator() async throws {
        Self.notify("com.apple.BiometricKit.enrollmentChanged", state: 1)
        try await Task.sleep(for: .milliseconds(500))
        #expect(LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
        #expect(FaceID.canLock())
        let matching = Task {
            try await Task.sleep(for: .seconds(1.5))
            Self.notify("com.apple.BiometricKit_Sim.pearl.match")
        }
        #expect(await FaceID.unlock())
        _ = try await matching.value

        // A face that doesn't match: still asking, then called off.
        let refusing = Task {
            try await Task.sleep(for: .seconds(1.5))
            Self.notify("com.apple.BiometricKit_Sim.pearl.nomatch")
        }
        let context = LAContext()
        let answer = Task { await FaceID.unlock(context) }
        _ = try await refusing.value
        try await Task.sleep(for: .seconds(1))
        context.invalidate()
        #expect(await answer.value == false)
    }

    nonisolated static func notify(_ name: String, state: UInt64? = nil) {
        if let state {
            var token: Int32 = 0
            notify_register_check(name, &token)
            notify_set_state(token, state)
            notify_cancel(token)
        }
        notify_post(name)
    }
}
