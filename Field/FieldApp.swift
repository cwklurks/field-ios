import SwiftUI
import UIKit

@main
struct FieldApp: App {
    @AppStorage("look") private var look: Look = .system
    @AppStorage("welcomed") private var welcomed = false
    /// Set by the tap that finishes the welcome. The screen hides on this,
    /// not on `welcomed`: `-welcomed NO` in the launch arguments outranks
    /// the app's own write, so the default would never read true.
    @State private var answered = false
    /// The welcome has handed over to the field under it.
    @State private var welcomeGone = false
    @State private var browser = Browser()
    @Environment(\.scenePhase) private var phase


    var body: some Scene {
        WindowGroup {
            ZStack {
                if Baseline.isOn {
                    BaselineView()
                } else {
                    // Built under the welcome too, so Continue has nothing
                    // to build: the field is there, waiting for focus.
                    BrowserView(browser: browser)
                    if !welcomeGone, answered || !welcomed {
                        Welcome(done: finishWelcome)
                    }
                }
            }
            .onAppear(perform: firstFrame)
            // At the root, so every sheet and page agrees with it.
            .preferredColorScheme(look.scheme)
            .dynamicTypeSize(...Ramp.cap)
            // No accent colour: anything the system would tint blue is ink.
            .tint(Palette.ink)
        }
        .onChange(of: phase) { _, phase in
            if phase == .background { browser.flush() }
        }
    }

    /// The first frame is committed at the end of the turn that laid it out,
    /// so the next turn is the first moment it's on its way to the screen.
    /// Only then does the browser start: the page's web view, or on a blank
    /// tab the field, whose focus sets up the keyboard.
    private func firstFrame() {
        DispatchQueue.main.async {
            Signpost.log.emitEvent(Signpost.firstFrame)
            if welcomed, !Baseline.isOn { browser.start() }
        }
    }

    /// Continue focuses the field that has been waiting under the welcome,
    /// and the welcome goes as the keyboard comes: a picture of it stays
    /// over the window and fades on the keyboard's own curve while the
    /// keyboard lifts the field out from under it (WelcomeCover). A blank
    /// tab builds no web view until it's quiet, so nothing heavy runs while
    /// that moves.
    private func finishWelcome() {
        let cover = WelcomeCover(covering: .shared)
        welcomed = true
        answered = true
        welcomeGone = true
        browser.start()
        cover?.fadeWithKeyboard()
    }
}

/// A picture of the window, over it, gone when the keyboard next comes up:
/// on the keyboard's curve, or on the settle curve if none comes soon (a
/// hardware keyboard).
@MainActor final class WelcomeCover: NSObject {
    private let picture: UIView
    private var waiting = false

    init?(covering app: UIApplication) {
        guard let window = app.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
            let picture = window.snapshotView(afterScreenUpdates: false) else { return nil }
        self.picture = picture
        super.init()
        window.addSubview(picture)
    }

    func fadeWithKeyboard() {
        waiting = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardShowing(_:)), name: UIResponder.keyboardWillShowNotification, object: nil
        )
        Task { [self] in
            try? await Task.sleep(for: FieldOpening.patience)
            fade(.settle)
        }
    }

    @objc private func keyboardShowing(_ note: Notification) {
        fade(SurfaceMotion.Curve(keyboard: note) ?? .settle)
    }

    private func fade(_ curve: SurfaceMotion.Curve) {
        guard waiting else { return }
        waiting = false
        NotificationCenter.default.removeObserver(self)
        SurfaceMotion.animate(curve) { self.picture.alpha = 0 } completion: { _ in
            self.picture.removeFromSuperview()
        }
    }
}
