import FieldKit
import LocalAuthentication
import UIKit

/// Private's lock, cover and capture blank, in the running app: FieldKit's
/// PrivateLock fed with what the scene does, and its shade put on screen.
///
/// The scene's notifications are heard on the thread that posts them, so the
/// cover is up before `sceneWillResignActive` and `sceneDidEnterBackground`
/// return, and so before UIKit takes the app switcher's snapshot. The shade
/// is a window of its own, made on the way into Private, so showing it is
/// only unhiding it.
@MainActor final class PrivateGate {
    private(set) var lock: PrivateLock
    let space: PrivateSpace
    /// The lock screen's "Your tabs": back to the everyday tabs, locked.
    var leave: () -> Void = {}
    /// The space was wiped (by "wipe instead" or the clock), and is empty.
    var wiped: () -> Void = {}

    var shade: PrivateLock.Shade { lock.shade }
    /// Something is over Private right now.
    var shadeShown: Bool { window?.showing != nil }

    private let defaults: UserDefaults
    private let authenticate: () async -> Bool
    private let canLock: () -> Bool
    private var window: PrivateShade?
    private var observers: [any NSObjectProtocol] = []
    private var capture: (any UITraitChangeRegistration)?
    private var wiping = false

    init(space: PrivateSpace, defaults: UserDefaults = .standard,
         authenticate: @escaping () async -> Bool = { await FaceID.unlock() },
         canLock: @escaping () -> Bool = { FaceID.canLock() }) {
        self.space = space
        self.defaults = defaults
        self.authenticate = authenticate
        self.canLock = canLock
        lock = PrivateLock()
        let center = NotificationCenter.default
        let heard: [(Notification.Name, PrivateLock.Event)] = [
            (UIScene.willDeactivateNotification, .resigned),
            (UIScene.didEnterBackgroundNotification, .backgrounded),
            (UIScene.didActivateNotification, .activated),
        ]
        // No queue: on the posting thread, before the post returns.
        observers = heard.map { name, event in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.heard(event) }
            }
        }
    }

    // MARK: - what the browser tells it

    /// Into Private. The shade is made now, while nothing is in a hurry.
    func entered() {
        lock.canLock = canLock()
        prepare()
        send(.entered)
    }

    /// Back to the everyday tabs: locked, or wiped.
    func left() {
        send(.left)
    }

    /// The lock screen's Unlock: Face ID, or the passcode.
    func unlock() async {
        guard send(.unlockTapped) == .authenticate else { return }
        let yes = await authenticate()
        send(.unlocked(yes))
    }

    /// Recording, mirroring or AirPlay started or stopped.
    func captureChanged(_ on: Bool) {
        send(.captured(on))
    }

    // MARK: -

    private func heard(_ event: PrivateLock.Event) {
        if event == .activated { lock.canLock = canLock() }
        send(event)
    }

    @discardableResult
    private func send(_ event: PrivateLock.Event) -> PrivateLock.Action? {
        let settings = PrivateSettings(defaults)
        lock.away = settings.away
        lock.wipeAfter = settings.wipeAfter
        if !wiping { lock.holding = space.holding }
        let action = lock.handle(event, now: .now)
        if action == .wipe { wipe() }
        show()
        return action
    }

    private func wipe() {
        guard !wiping else { return }
        wiping = true
        Task {
            await space.wipe()
            wiping = false
            send(.wiped)
            wiped()
        }
    }

    private func show() {
        let shade = lock.shade
        guard shade != .none else {
            window?.hide(animated: true)
            return
        }
        if window == nil { prepare() }
        // The keyboard is drawn over every window the app has, the shade's
        // too, and the switcher's snapshot would have it, suggestions and
        // all: it goes now, without its slide.
        UIView.performWithoutAnimation {
            window?.windowScene?.windows.forEach { $0.endEditing(true) }
        }
        window?.show(shade)
    }

    /// The shade's window, and the watch on screen capture, on the app's scene.
    private func prepare() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if window == nil {
            let window = PrivateShade(windowScene: scene)
            window.unlock = { [weak self] in Task { await self?.unlock() } }
            window.leave = { [weak self] in self?.leave() }
            self.window = window
        }
        guard capture == nil else { return }
        capture = scene.registerForTraitChanges([UITraitSceneCaptureState.self]) { [weak self] (scene: UIWindowScene, _) in
            self?.captureChanged(scene.traitCollection.sceneCaptureState == .active)
        }
        // Already recording on the way in.
        if scene.traitCollection.sceneCaptureState == .active { _ = lock.handle(.captured(true), now: .now) }
    }
}

/// Face ID, or the passcode when it fails or there's none: a new context
/// for each unlock, so one success never carries over to the next.
enum FaceID {
    static func canLock() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static func unlock(_ context: LAContext = LAContext()) async -> Bool {
        await withCheckedContinuation { done in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Private.") { yes, _ in
                done.resume(returning: yes)
            }
        }
    }
}
