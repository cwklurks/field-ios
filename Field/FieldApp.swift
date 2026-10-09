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
                if SuggestionFixture.isOn {
                    SuggestionFixture()
                } else if Baseline.isOn {
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
            // A link from another app, at a cold launch too: held until the
            // browser has started and the welcome is done (Arrivals).
            .onOpenURL { browser.arrivals.received($0) }
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
            // Before the browser starts: the blocker watches the keyboard,
            // and has to see it come up for the field.
            if !Baseline.isOn, !SuggestionFixture.isOn {
                ContentBlocking.shared.prepare()
                Guarded.load()
            }
            if !welcomed { browser.arrivals.welcome(showing: true) }
            browser.arrivals.receiveFromLaunchArguments()
            if welcomed, !Baseline.isOn, !SuggestionFixture.isOn { browser.start() }
        }
    }

    /// Continue: the welcome starts to go on the frame after the tap, a
    /// picture of it fading over the window (WelcomeCover), and only once
    /// that fade is on its way does the browser start, since focusing the
    /// field holds the main thread. The field comes in with the keyboard
    /// (Browser.leaveWelcome). A blank tab builds no web view until it's
    /// quiet, so nothing heavy runs while that moves.
    private func finishWelcome() {
        WelcomeCover(covering: .shared)?.fade()
        browser.leaveWelcome()
        welcomed = true
        answered = true
        welcomeGone = true
        AfterCommit.run { [browser] in
            browser.start()
            browser.arrivals.welcome(showing: false)
        }
    }
}

/// A picture of the window, over it, fading at once.
@MainActor final class WelcomeCover {
    private let picture: UIView

    init?(covering app: UIApplication) {
        guard let window = app.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
            let picture = window.snapshotView(afterScreenUpdates: false) else { return nil }
        self.picture = picture
        window.addSubview(picture)
    }

    func fade() {
        SurfaceMotion.animate(.quick) { self.picture.alpha = 0 } completion: { _ in
            self.picture.removeFromSuperview()
        }
    }
}
