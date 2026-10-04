import FieldKit
import SwiftUI
import UIKit

/// Tidy's sheets, put up from UIKit: the preview (TidySheet) and the stale
/// tabs' review (StaleSheet). Built and drawn once while nothing moves, as
/// Settings and Saved are (SettingsSheet, SavedSheets): SwiftUI builds a
/// sheet's content on the tap and the sheet waits for it before it moves.
/// Kept from then on, and given a new draft on each opening.
@MainActor
enum TidySheets {
    private static var host: Host?
    private static var reading: Task<Void, Never>?
    #if DEBUG
    /// The draft on screen, and its Apply: the harness drives them.
    private(set) static var shownDraft: TidyDraft?
    private(set) static var shownApply: (() -> Void)?
    private(set) static var shownHost: UIViewController?
    #endif

    /// Two seconds on, when no finger is down and `busy` says nothing else
    /// is going on, the sheet is built and drawn out of sight.
    static func prepareSoon(unless busy: @escaping @MainActor () -> Bool, tries: Int = 0) {
        guard tries < 20 else { return }
        Timer.scheduledTimer(withTimeInterval: tries == 0 ? 2 : 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard host == nil else { return }
                if busy() { return prepareSoon(unless: busy, tries: tries + 1) }
                _ = prepared()
            }
        }
    }

    /// Tidy: the engine reads `tabs` (never private ones) and the groups
    /// stream into the sheet. Apply hands them to `flow`.
    static func show(_ tabs: [TabInfo], flow: TidyFlow, engine: TidyEngine = .shared) {
        let draft = TidyDraft(tabs: tabs)
        guard present(draft, flow: flow) else { return }
        reading = Task {
            for await suggestion in engine.stream(tabs) {
                withAnimation(Motion.calm(Motion.settle)) { draft.receive(suggestion) }
            }
        }
    }

    /// "Add similar tabs" to `group`, which has `members`, from `loose`.
    static func showSimilar(to group: Session.Group, members: [TabInfo], among loose: [TabInfo],
                            flow: TidyFlow, engine: TidyEngine = .shared) {
        let draft = TidyDraft(tabs: members + loose, mode: .similar(group: group.id, name: group.name))
        guard present(draft, flow: flow) else { return }
        reading = Task {
            let found = await engine.similar(named: group.name, members: members, among: loose)
            guard !Task.isCancelled else { return }
            // Nothing to show: a toast says it, not a sheet with a dead Add.
            guard found.contains(where: { draft.info[$0] != nil }) else {
                host?.dismiss(animated: true)
                return flow.announce("No other tabs look like these.")
            }
            withAnimation(Motion.calm(Motion.settle)) { draft.receiveSimilar(found) }
        }
    }

    /// The stale tabs' review: `tabs` checked, Close closes the checked ones.
    static func showStale(_ tabs: [TabInfo], line: String, close: @escaping ([UUID]) -> Void) {
        let sheet = Host(rootView: AnyView(EmptyView()))
        sheet.rootView = AnyView(StaleSheet(tabs: tabs, line: line, onClose: { [weak sheet] ids in
            sheet?.dismiss(animated: true)
            close(ids)
        }, onCancel: { [weak sheet] in sheet?.dismiss(animated: true) }).rooted())
        sheet.view.backgroundColor = Palette.UI.ground
        top?.present(sheet, animated: true)
    }

    @discardableResult
    private static func present(_ draft: TidyDraft, flow: TidyFlow) -> Bool {
        let host = prepared()
        guard host.presentingViewController == nil, let top else { return false }
        reading?.cancel()
        let apply = { [weak host] in
            // The sheet goes and the grid regroups in the same moment.
            host?.dismiss(animated: true)
            flow.apply(draft)
        }
        #if DEBUG
        shownDraft = draft
        shownApply = apply
        shownHost = host
        #endif
        host.rootView = AnyView(TidySheet(
            draft: draft,
            onApply: apply,
            onCancel: { [weak host] in host?.dismiss(animated: true) }
        ).rooted())
        host.onDismiss = { reading?.cancel() }
        top.present(host, animated: true)
        return true
    }

    // MARK: - hosts

    private static func prepared() -> Host {
        if let host { return host }
        let made = Host(rootView: AnyView(EmptyView()))
        made.view.backgroundColor = Palette.UI.ground
        if let sheet = made.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        host = made
        // Drawn once with a group in it, so fonts, symbols and the row's
        // views are all made before the first tap.
        let sample = TabInfo(id: UUID(), title: "Field", url: URL(string: "https://field.invalid/")!)
        let draft = TidyDraft(tabs: [sample])
        draft.receive(TidySuggestion(groups: [TidyGroup(name: "Field", ids: [sample.id])], engine: .rules, done: true))
        made.rootView = AnyView(TidySheet(draft: draft, onApply: {}, onCancel: {}).rooted())
        guard let window else { return made }
        made.view.frame = window.bounds
        made.view.accessibilityElementsHidden = true
        window.insertSubview(made.view, at: 0)
        made.view.layoutIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            made.view.accessibilityElementsHidden = false
            if made.presentingViewController == nil { made.view.removeFromSuperview() }
        }
        return made
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    private static var top: UIViewController? {
        guard var top = window?.rootViewController else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }

    /// Says when it has gone, however it went: Cancel, Apply or a swipe down.
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
