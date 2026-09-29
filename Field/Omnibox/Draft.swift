// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import FieldKit

/// What is in the field: what was typed, and the rest of the best match after
/// it, selected, so the next letter replaces it and Return takes it.
///
/// UIKit makes every edit; this only answers it. Kept apart from the field so
/// the rules can be tested without one.
struct Draft: Equatable {
    enum Cause { case typed, deleted, pasted }

    /// What the person put there, including an ending they kept by moving off it.
    private(set) var typed: String
    /// The part the field finished for them; empty when it finished nothing.
    private(set) var ending = ""
    /// In UTF-16 offsets into `text`, as UIKit counts.
    private(set) var selection: Range<Int>
    /// The place `text` spells when the field finished it, so Return goes to
    /// the address it was reached at rather than one guessed from the words.
    private(set) var match: Suggestion?

    var text: String { typed + ending }

    /// All of it selected, so the first letter typed replaces it.
    init(text: String = "") {
        typed = text
        selection = 0..<text.utf16.count
    }

    /// UIKit has changed the text; `text` and `selection` are what it now holds.
    mutating func edited(
        to text: String,
        selection: Range<Int>,
        marked: Bool,
        cause: Cause,
        complete: (String) -> (ending: String, suggestion: Suggestion)?
    ) {
        typed = text
        ending = ""
        match = nil
        self.selection = selection

        // Only a letter typed at the end is finished for. A backspace would get
        // back the very letters it took off, and the field could never be
        // shortened. A paste already says all it means. Marked text isn't
        // letters yet, and writing into it would break the composition.
        let end = text.utf16.count
        guard cause == .typed, !marked, selection == end..<end,
              let hit = complete(text), !hit.ending.isEmpty else { return }
        ending = hit.ending
        match = hit.suggestion
        self.selection = end..<(end + hit.ending.utf16.count)
    }

    /// The caret or the selection moved and the text didn't. Moving off the
    /// ending keeps it: what the field says is what it now holds.
    mutating func selected(_ selection: Range<Int>) {
        guard selection != self.selection else { return }
        self.selection = selection
        typed += ending
        ending = ""
    }
}
