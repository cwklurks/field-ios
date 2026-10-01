// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI
import UIKit
import os

/// The field itself, in UIKit.
///
/// SwiftUI's TextField can hold a string and nothing else, and the whole point
/// here is the part you didn't type: the rest of the address, already there and
/// selected, so carrying on typing replaces it and Return accepts it. That
/// needs a real text field and its delegate.
///
/// There is one, made once and kept by the surface (see FieldSurface), so a
/// tap on the address has nothing to build before it shows.
enum AddressField {
    static func make(_ coordinator: Coordinator) -> Input {
        let field = Input()
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)

        // Ramp.field, which follows body, and stops where the ramp does.
        field.font = font
        field.adjustsFontForContentSizeCategory = true
        field.textColor = Palette.UI.ink
        // The caret, and the selection the ending wears: ink, never a blue.
        field.tintColor = Palette.UI.ink
        // UIKit's own placeholder grey is a colour of its own; this is the
        // Mac's, a third of the ink.
        field.attributedPlaceholder = NSAttributedString(
            string: "Search or enter an address",
            attributes: [.foregroundColor: Self.ink(0.3)]
        )
        Self.keyboard(for: field)
        field.accessibilityIdentifier = "field"

        field.onTouch = { [weak field] in
            guard let field else { return }
            coordinator.unfold(field)
        }
        field.page = { coordinator.omnibox.page }
        coordinator.field = field
        return field
    }

    /// Ramp.field, scaled with body up to the ramp's cap.
    static var font: UIFont {
        let base = UIFont.systemFont(ofSize: Ramp.field.size)
        let metrics = UIFontMetrics(forTextStyle: .body)
        let largest = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
        return metrics.scaledFont(for: base, maximumPointSize: metrics.scaledValue(for: base.pointSize, compatibleWith: largest))
    }

    /// Addresses and search words, not prose: nothing may change a letter
    /// behind your back or finish a word the field is finishing itself. The
    /// keyboard warmed at launch takes the same, so the one that comes is the
    /// one that was loaded.
    static func keyboard(for field: UITextField) {
        field.keyboardType = .webSearch
        field.returnKeyType = .go
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.inlinePredictionType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
    }

    /// Ink at a strength, in whichever look the field is drawn: an alpha
    /// taken off a dynamic colour settles on the look it was made in.
    static func ink(_ alpha: CGFloat) -> UIColor {
        UIColor { Palette.UI.ink.resolvedColor(with: $0).withAlphaComponent(alpha) }
    }

    /// The tenth of ink the field's proposal wears, as the Mac selects it.
    static let selected = AddressField.ink(0.12)

    /// Knows when an edit was a paste, and draws the ending it proposes.
    final class Input: UITextField {
        /// Before UIKit acts on a touch, or on a key that isn't typing.
        var onTouch: (() -> Void)?
        /// The page the field still stands for, untouched.
        var page: (() -> URL?)?
        /// Whether the field is up to be typed in. Never focused when it
        /// isn't: UIKit hands focus back to whatever had it before a sheet,
        /// and a field closed meanwhile would take the keyboard while hidden.
        var mayFocus: () -> Bool = { true }
        private(set) var pasting = false
        /// Set while the selection is the field's own proposal, which wears
        /// its tenth of ink as a background instead. With no rects, UIKit has
        /// nowhere to draw its highlight or the handles, and there is no
        /// public way to hide the handles alone.
        var proposing = false

        /// The rest of the address, drawn after the text rather than written
        /// into it: see Coordinator.apply.
        private(set) var ending: String?
        private let label = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.backgroundColor = AddressField.selected
            label.isHidden = true
            label.isAccessibilityElement = false
            addSubview(label)
            addGestureRecognizer(TouchDown { [weak self] in self?.onTouch?() })
        }

        required init?(coder: NSCoder) { fatalError() }

        override var canBecomeFirstResponder: Bool {
            mayFocus() && super.canBecomeFirstResponder
        }

        override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
            proposing ? [] : super.selectionRects(for: range)
        }

        /// While set, a resign asked for from outside (UIKit's, as a swiped
        /// keyboard finishes) is handed to it to carry out when it chooses.
        var resignLater: ((@escaping () -> Void) -> Void)?

        override func resignFirstResponder() -> Bool {
            guard let later = resignLater else { return super.resignFirstResponder() }
            resignLater = nil
            later { [weak self] in _ = self?.resignFirstResponder() }
            return true
        }

        /// All of an untouched field is the page's whole address, not the
        /// shortened one it shows, and without its tracking parameters.
        override func copy(_ sender: Any?) {
            guard let page = page?(), let range = selectedTextRange,
                  compare(range.start, to: beginningOfDocument) == .orderedSame,
                  compare(range.end, to: endOfDocument) == .orderedSame else { return super.copy(sender) }
            Guarded.copy(page)
        }

        override func paste(_ sender: Any?) {
            pasting = true
            defer { pasting = false }
            super.paste(sender)
        }

        /// Keys that move or select act on the text as it would be written,
        /// so a drawn ending is written in first. Typing, a backspace and
        /// Return need nothing but what is there.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if ending != nil, presses.contains(where: { Self.moves($0.key) }) { onTouch?() }
            super.pressesBegan(presses, with: event)
        }

        private static func moves(_ key: UIKey?) -> Bool {
            guard let key else { return false }
            if key.modifierFlags.contains(.command) { return true }
            switch key.keyCode {
            case .keyboardLeftArrow, .keyboardRightArrow, .keyboardUpArrow, .keyboardDownArrow,
                 .keyboardHome, .keyboardEnd, .keyboardPageUp, .keyboardPageDown, .keyboardDeleteForward:
                return true
            default:
                return false
            }
        }

        /// Whether `ending` can be drawn after the text: the text reads left
        /// to right, and there's room for it without scrolling.
        func fits(_ ending: String) -> Bool {
            guard let font, let line = line(),
                  baseWritingDirection(for: endOfDocument, in: .backward) != .rightToLeft else { return false }
            let width = (ending as NSString).size(withAttributes: [.font: font]).width
            return line.maxX + width <= textRect(forBounds: bounds).maxX
        }

        /// Some of the text has the proposal's tenth of ink behind it.
        var wearsPaint: Bool {
            guard let text = attributedText, text.length > 0 else { return false }
            var found = false
            text.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: text.length)) { value, _, stop in
                if value != nil { found = true; stop.pointee = true }
            }
            return found
        }

        /// Where the text is drawn, in the field: the ending goes on after it,
        /// just where a written one would.
        private func line() -> CGRect? {
            guard hasText, let all = textRange(from: beginningOfDocument, to: endOfDocument) else { return nil }
            let rect = firstRect(for: all)
            return rect.isNull || rect.isInfinite ? nil : rect
        }

        /// Draws `ending` after the text, or stops drawing it. The caret is
        /// hidden meanwhile, as it is while the ending is a selection.
        func propose(_ ending: String?) {
            guard ending != self.ending else { return }
            let was = self.ending
            self.ending = ending
            if let ending {
                label.text = ending
                label.font = font
                label.textColor = textColor
                label.isHidden = false
                if was == nil { tintColor = .clear }
                place()
            } else {
                label.isHidden = true
                label.text = nil
                tintColor = Palette.UI.ink
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            place()
        }

        private func place() {
            guard ending != nil, let line = line() else { return }
            // As tall as the paint on a written ending: the font's line.
            let height = font?.lineHeight ?? line.height
            label.frame = CGRect(x: line.maxX, y: line.midY - height / 2, width: ceil(label.intrinsicContentSize.width), height: height)
        }

        override var accessibilityValue: String? {
            get { (super.accessibilityValue ?? text ?? "") + (ending ?? "") }
            set { super.accessibilityValue = newValue }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        /// A new one for each opening.
        var omnibox: Omnibox
        var onGo: (URL) -> Void = { _ in }
        /// After each edit is answered, before it's drawn: the rows may have changed.
        var onEdited: () -> Void = {}
        /// Return, with nothing to go to.
        var onRefused: () -> Void = {}
        /// The field lost focus.
        var onEnded: () -> Void = {}
        weak var field: Input?

        /// What the edit UIKit is about to make is, read before it makes it.
        private var cause: Draft.Cause?
        /// Set while the field is written from here, so its echo isn't taken
        /// for the person moving the caret.
        private var applying = false
        /// `field.keystroke` intervals waiting for the commit that shows them.
        private var keystrokes: [OSSignpostIntervalState] = []
        private var commit: CFRunLoopObserver?

        /// Some of the text wears the tenth of ink.
        private var painted = false

        /// `launch.fieldReady` is the first time only.
        private static var ready = false

        init(omnibox: Omnibox) {
            self.omnibox = omnibox
            super.init()
            Keyboard.watch()
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardUp), name: UIResponder.keyboardDidShowNotification, object: nil
            )
        }

        /// Takes typing from here on. The keyboard may already be up (it
        /// stays up going from a page's field to this one), and then no
        /// keyboard notice is coming.
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !Self.ready {
                Self.ready = true
                Signpost.log.emitEvent(Signpost.fieldReady)
            }
            if Keyboard.up { FieldOpening.end() }
        }

        /// Closed before any keyboard came (a hardware one): the opening
        /// still ends.
        func textFieldDidEndEditing(_ textField: UITextField) {
            FieldOpening.end()
            onEnded()
        }

        func textField(_ textField: UITextField, shouldChangeCharactersInRanges ranges: [NSValue], replacementString string: String) -> Bool {
            // A drawn ending isn't in the text, so UIKit would take the letter
            // before it. Deleting a selection takes the selection and nothing
            // else: the ending goes, and the field keeps what it holds.
            if let field = textField as? Input, field.ending != nil, string.isEmpty {
                let end = omnibox.draft.typed.utf16.count
                edit(field, to: omnibox.draft.typed, selection: end..<end, cause: .deleted)
                return false
            }
            let pasting = (textField as? Input)?.pasting == true
            cause = string.isEmpty ? .deleted : pasting ? .pasted : .typed
            return true
        }

        @objc func changed(_ field: Input) {
            edit(field, to: field.text ?? "", selection: selection(in: field), cause: cause ?? .typed)
            cause = nil
        }

        private func edit(_ field: Input, to text: String, selection: Range<Int>, cause: Draft.Cause) {
            keystrokes.append(Signpost.log.beginInterval(Signpost.keystroke, id: Signpost.log.makeSignpostID()))
            if commit == nil {
                // Last before the main thread sleeps, after Core Animation's
                // commit. Not a display link: a new one's first call comes a
                // frame late, and can come before the commit it should follow.
                let observer = CFRunLoopObserverCreateWithHandler(
                    nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
                ) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.drawn() }
                }
                CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                commit = observer
            }

            let draft = omnibox.edited(to: text, selection: selection, marked: field.markedTextRange != nil, cause: cause)
            apply(draft, to: field)
            onEdited()
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            // The text changing moves the caret too; `changed` answers that.
            guard !applying, let field = textField as? Input, field.text == held(by: field) else { return }
            let selection = selection(in: field)
            omnibox.selected(selection)
            // Moving off a drawn ending keeps it, so it's written in, where
            // the caret can go. A painted selection is yours now, so drawn as
            // UIKit draws any selection you make.
            if field.ending != nil || painted {
                field.propose(nil)
                show(omnibox.draft.text, selecting: selection, proposed: false, in: field)
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let url = omnibox.submit() { onGo(url) } else { onRefused() }
            return false
        }

        /// Shows the draft the field opens with, the address selected,
        /// before the field has focus: what the tap shows at once.
        func show(_ field: Input) {
            apply(omnibox.draft, to: field)
        }

        /// Focused, holding the draft it opens with. It's written before
        /// focus, so the keyboard starts from it rather than hearing it
        /// rewritten. Taking focus, UIKit puts the caret at the end; that's its
        /// move, not the person's, and taken for theirs it would unselect the
        /// address before it was ever shown.
        func open(_ field: Input) {
            apply(omnibox.draft, to: field)
            applying = true
            field.becomeFirstResponder()
            applying = false
            select(omnibox.draft.selection, in: field)
        }

        /// Never into marked text, which is the keyboard's until it's done.
        ///
        /// An ending for what was just typed at the end is drawn after the
        /// text rather than written into it. Writing the field in the middle
        /// of the keyboard's own edit makes the keyboard read the whole field
        /// again, which costs more than the rest of the keystroke together.
        func apply(_ draft: Draft, to field: Input) {
            guard field.markedTextRange == nil else {
                // The keyboard's selection now; the text is repainted once the
                // composition is done.
                field.proposing = false
                field.propose(nil)
                return
            }
            // A letter typed over the painted ending takes the place of the
            // paint, or wears it; only in the second case is a rewrite owed.
            if painted, !field.wearsPaint { painted = false }
            let end = draft.typed.utf16.count
            if !draft.ending.isEmpty, !painted, field.text == draft.typed,
               selection(in: field) == end..<end, field.fits(draft.ending) {
                field.propose(draft.ending)
                return
            }
            field.propose(nil)
            // Only the field selects a range after an edit: the ending, or the
            // address it opened with.
            show(draft.text, selecting: draft.selection, proposed: !draft.selection.isEmpty, in: field)
        }

        /// A drawn ending becomes a selected one, written in, before anything
        /// but typing reaches the field: a touch, or a key that moves. UIKit
        /// then does with it what it does with any selection.
        func unfold(_ field: Input) {
            guard field.ending != nil else { return }
            field.propose(nil)
            show(omnibox.draft.text, selecting: omnibox.draft.selection, proposed: true, in: field)
        }

        /// What the field holds as the draft stands: all of it, or, while the
        /// ending is drawn, what was typed.
        private func held(by field: Input) -> String {
            field.ending == nil ? omnibox.draft.text : omnibox.draft.typed
        }

        /// What the field proposes is selected as the Mac selects it: a tenth
        /// of ink behind it, and no handles, since it is nothing you picked out.
        private func show(_ text: String, selecting selection: Range<Int>, proposed: Bool, in field: Input) {
            if proposed || painted || field.text != text {
                applying = true
                let styled = NSMutableAttributedString(string: text, attributes: field.defaultTextAttributes)
                if proposed {
                    styled.addAttribute(.backgroundColor, value: AddressField.selected, range: NSRange(selection))
                }
                field.attributedText = styled
                painted = proposed
                applying = false
            }
            field.proposing = proposed
            select(selection, in: field)
            // The next letter replaces the ending without taking its paint,
            // so it can be drawn again rather than written.
            if proposed { field.typingAttributes = field.defaultTextAttributes }
        }

        private func select(_ selection: Range<Int>, in field: UITextField) {
            guard self.selection(in: field) != selection,
                  let start = field.position(from: field.beginningOfDocument, offset: selection.lowerBound),
                  let end = field.position(from: start, offset: selection.count) else { return }
            applying = true
            field.selectedTextRange = field.textRange(from: start, to: end)
            applying = false
        }

        private func selection(in field: UITextField) -> Range<Int> {
            guard let range = field.selectedTextRange else { return 0..<0 }
            let start = field.offset(from: field.beginningOfDocument, to: range.start)
            let end = field.offset(from: field.beginningOfDocument, to: range.end)
            return start..<max(start, end)
        }

        /// The text and the rows a keystroke changed are laid out and handed to
        /// the render server together, for the coming frame.
        private func drawn() {
            for state in keystrokes { Signpost.log.endInterval(Signpost.keystroke, state) }
            keystrokes = []
            if let commit { CFRunLoopObserverInvalidate(commit) }
            commit = nil
        }

        /// Focused, with the keyboard up: the field has opened.
        @objc private func keyboardUp() {
            guard field?.isFirstResponder == true else { return }
            FieldOpening.end()
        }
    }
}

/// Sees every touch on the field as it begins, and leaves it to the field's
/// own gestures.
private final class TouchDown: UIGestureRecognizer {
    private let began: () -> Void

    init(_ began: @escaping () -> Void) {
        self.began = began
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        began()
        state = .failed
    }
}

/// Runs something at the next frame, once the one being made has gone out.
final class NextFrame: NSObject {
    private var body: (() -> Void)?
    private var link: CADisplayLink?

    static func run(_ body: @escaping () -> Void) {
        let next = NextFrame()
        next.body = body
        let link = CADisplayLink(target: next, selector: #selector(fire))
        next.link = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func fire() {
        link?.invalidate()
        link = nil
        let body = body
        self.body = nil
        body?()
    }
}
