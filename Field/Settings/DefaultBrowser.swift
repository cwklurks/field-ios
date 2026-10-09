import SwiftUI
import UIKit

/// Settings' Default browser section: whether Field opens the links tapped
/// in other apps, and the way to the system's own choice. Shown only in a
/// build that carries the default-browser entitlement (FIELD_DEFAULT_BROWSER,
/// project.default-browser.yml); without it iOS never offers Field there.
struct DefaultBrowserSection: View {
    @State private var isDefault = DefaultBrowser.known
    /// Gone to the system's settings from here: asked again on the way back.
    @State private var away = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                away = true
                DefaultBrowser.openSettings()
            } label: {
                Text("Choose Default Browser")
                    .ramp(.row)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.defaultBrowser")
            Text(Self.note(isDefault))
                .ramp(.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { isDefault = DefaultBrowser.check() }
        .onChange(of: phase) { _, phase in
            guard phase == .active, away else { return }
            away = false
            isDefault = DefaultBrowser.check(fresh: true)
        }
    }

    static func note(_ isDefault: Bool?) -> String {
        switch isDefault {
        case true: "Links you tap in other apps open in Field."
        case false: "Links you tap in other apps open in another browser."
        case nil: "Choose Field in Default Apps to open links from other apps here."
        }
    }
}

/// Whether Field is the default browser, asked of iOS sparingly: it limits
/// how often an app may ask, and says when it may again.
@MainActor enum DefaultBrowser {
    /// The last answer, kept for the session.
    private(set) static var known: Bool?
    private static var notBefore = Date.distantPast

    /// Asked again only when `fresh` (back from the system's settings), and
    /// never before iOS allows it.
    static func check(fresh: Bool = false) -> Bool? {
        guard known == nil || fresh, Date.now >= notBefore else { return known }
        do {
            known = try UIApplication.shared.isDefault(.webBrowser)
        } catch {
            let retry = (error as NSError).userInfo[UIApplication.CategoryDefaultError.retryAvailableDateErrorKey]
            if let retry = retry as? Date { notBefore = retry }
        }
        return known
    }

    /// The system's Default Apps, where the choice is made.
    static func openSettings() {
        guard let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
