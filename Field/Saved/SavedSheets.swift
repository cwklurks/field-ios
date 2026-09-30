import FieldKit
import SwiftUI
import UIKit

/// Saved's two sheets, put up from UIKit: the list, and the one after Save.
/// Each kind is built and drawn once while nothing moves, as Settings is
/// (SettingsSheet): SwiftUI builds a sheet's content on the tap, and the
/// sheet waits for it before it moves, longest by far the first time. The
/// list is kept from then on, as Settings is: built anew, it started 6
/// frames after the lift. SavedView starts it clean on each opening. The
/// Save sheet is made anew each time.
@MainActor
enum SavedSheets {
    /// The list, kept once built.
    private static var list: Host?
    private static var warmed = false

    /// Two seconds on, when no finger is down and `busy` says nothing else
    /// is going on, both sheets are built and drawn out of sight.
    static func prepareSoon(_ store: SavedStore, unless busy: @escaping @MainActor () -> Bool, tries: Int = 0) {
        guard tries < 20 else { return }
        Timer.scheduledTimer(withTimeInterval: tries == 0 ? 2 : 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard !warmed else { return }
                if busy() { return prepareSoon(store, unless: busy, tries: tries + 1) }
                prepare(store)
            }
        }
    }

    /// Also loads the sentence model and reads what's saved with it, off
    /// the main thread, so the first suggestion is as quick as the rest.
    static func prepare(_ store: SavedStore) {
        guard !warmed else { return }
        warmed = true
        let host = Host(rootView: AnyView(SavedView(store: store, onOpen: { _ in }, onDone: {}).rooted()))
        host.view.backgroundColor = Palette.UI.ground
        list = drawn(host)
        Task { await FolderSuggester.shared.warm(store.saved) }
        // A page that isn't saved, so the sheet, going, keeps nothing.
        var elsewhere = Saved()
        guard let page = elsewhere.save(URL(string: "https://field.invalid/")!, title: "Field") else { return }
        _ = drawn(Host(rootView: AnyView(SaveSheet(store: store, page: page) {}.rooted())))
    }

    /// Everything saved, from the tab grid's row or the new tab. `start` is
    /// the filter it opens on; `onOpen` is a page chosen, as the sheet goes.
    static func showList(_ store: SavedStore, start: SavedFilter = .all,
                         onOpen: @escaping (URL) -> Void, onDismiss: @escaping () -> Void = {}) {
        guard list?.presentingViewController == nil, let top else { return }
        let host = list ?? Host(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = Palette.UI.ground
        list = host
        host.rootView = AnyView(SavedView(
            store: store,
            onOpen: { [weak host] url in
                // The sheet goes and the page starts in the same moment.
                host?.dismiss(animated: true)
                onOpen(url)
            },
            onDone: { [weak host] in host?.dismiss(animated: true) },
            start: start
        ).rooted())
        host.onDismiss = onDismiss
        top.present(host, animated: true)
    }

    /// Save: the page is saved there and then, and the sheet comes up to
    /// tidy it. A page saved already gets the sheet alone. False for
    /// anything that isn't a web page.
    @discardableResult
    static func save(_ url: URL, title: String, in store: SavedStore, onDismiss: @escaping () -> Void = {}) -> Bool {
        guard let page = store.save(url, title: title) else { return false }
        guard let top else { return true }
        let host = Host(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(SaveSheet(store: store, page: page) { [weak host] in
            host?.dismiss(animated: true)
        }.rooted())
        host.view.backgroundColor = Palette.UI.ground
        host.onDismiss = onDismiss
        if let sheet = host.sheetPresentationController {
            // The height the sheet's rows need, over the home indicator.
            sheet.detents = [.custom(identifier: .init("save")) { _ in SaveSheet.height }]
            sheet.prefersGrabberVisible = false
        }
        top.present(host, animated: true)
        return true
    }

    // MARK: - hosts

    /// A hosting view builds nothing out of a window, and the first opening
    /// would wait for its pictures to reach the screen, so it's laid out and
    /// drawn once under the app's own view, where it can't be seen.
    private static func drawn(_ host: Host) -> Host {
        guard let window else { return host }
        host.view.frame = window.bounds
        host.view.accessibilityElementsHidden = true
        window.insertSubview(host.view, at: 0)
        host.view.layoutIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            host.view.accessibilityElementsHidden = false
            if host.presentingViewController == nil { host.view.removeFromSuperview() }
        }
        return host
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    private static var top: UIViewController? {
        guard var top = window?.rootViewController else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }

    /// Says when it has gone, however it went: Done or a swipe down.
    final class Host: UIHostingController<AnyView> {
        var onDismiss: () -> Void = {}

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if presentingViewController == nil { onDismiss() }
        }
    }
}

private extension View {
    /// What a sheet would take from the app's root, which one UIKit puts up
    /// doesn't.
    func rooted() -> some View {
        tint(Palette.ink).dynamicTypeSize(...Ramp.cap)
    }
}
