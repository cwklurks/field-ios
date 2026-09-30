import SwiftUI

/// The page, with the bar floating over its bottom edge, or the field in the
/// bar's place.
struct BrowserView: View {
    let browser: Browser

    var body: some View {
        ZStack(alignment: .bottom) {
            StageView(tabs: browser.tabs, bar: browser.bar) {
                // Straight from the tap, not from inside SwiftUI's next update.
                browser.settingsShown = true
                SettingsSheet.present { browser.settingsShown = false }
            }
                // Edge to edge, under the status bar too, as in Safari: the
                // page is one surface from top to bottom.
                .ignoresSafeArea(.container)
                .ignoresSafeArea(.keyboard)

            if let failure = browser.tab.failure, !browser.tabs.gridShown {
                Trouble(message: failure, retry: browser.tab.retry)
            }

            if !browser.tabs.gridShown {
                Toast(toaster: browser.toaster)
                    .padding(.bottom, Bar.height + 14)
            }

            // The bar, which is also the field: one surface on the keyboard.
            // It lays itself out against the window and the keyboard.
            FieldSurfaceHost(browser: browser)
                .ignoresSafeArea()
                // The grid has its own row along the bottom; the Stage fades
                // the bar in its place, on the grid's own timeline.
                .allowsHitTesting(!browser.tabs.gridShown)
        }
        .background(Palette.ground)
        .background { if TouchMarks.isOn { TouchMarksInstaller() } }
        .modifier(StatusTone(tone: browser.fieldOpen || browser.tabs.gridShown || browser.tab.failure != nil ? nil : browser.tab.tone))
        // Settings is made ahead of the tap (SettingsSheet), but never
        // between keystrokes or under a coasting page.
        .onAppear {
            SettingsSheet.prepareSoon {
                let scroll = browser.tab.web?.scrollView
                return browser.fieldOpen || scroll?.isTracking == true || scroll?.isDecelerating == true
            }
        }
    }
}

/// The status bar over the page takes the page's tone, since the page runs
/// under it: dark text over a white page even in a dark app. Over anything
/// Field draws itself (the field, an error) it's the app's own.
private struct StatusTone: ViewModifier {
    let tone: ColorScheme?

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.toolbarColorScheme(tone, for: .statusBar)
        } else {
            content
        }
    }
}
