import Foundation

// What may leave the phone while you type, and the one place that decides.
// The answer is no unless the switch is on, the space isn't Private, and the
// words are words: two letters or more, not an address, not something that
// reads as a secret, and not the start of somewhere the field already knows.
public enum Suggest {
    /// The switch in Settings, until it is moved.
    public static let enabledByDefault = true
    /// Where the switch is kept.
    public static let defaultsKey = "suggest"

    /// Longer than this is a paste, not a question.
    static let longest = 100

    /// The engine's suggest address for what was typed, or nil when nothing
    /// may be sent. `near` is what the field already offers from the phone.
    public static func request(
        for typed: String, engine: Engine, privately: Bool, enabled: Bool, near: [Suggestion] = []
    ) -> URL? {
        guard enabled, !privately else { return nil }
        let words = tidy(typed)
        guard mayLeave(words), !headingToAPlace(words, near: near) else { return nil }
        return engine.suggestURL(for: words)
    }

    /// Words fit to be sent anywhere, or kept: neither an address nor a secret.
    static func mayLeave(_ words: String) -> Bool {
        words.count >= 2 && words.count <= longest && !looksAddressLike(words) && !looksSecret(words)
    }

    /// A partial address is still an address. Check each token too, so a
    /// pasted URL beside words does not become a suggestion request.
    private static func looksAddressLike(_ words: String) -> Bool {
        words.split(separator: " ").contains { token in
            token.contains { ".:/@\\?#[]".contains($0) }
                || token.lowercased() == "localhost"
                || Address.url(from: String(token)) != nil
        }
    }

    /// Spaces round and runs of them inside taken out.
    static func tidy(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// One word, which a place the field offers starts with: an address
    /// half typed, which will be one in a few more letters.
    private static func headingToAPlace(_ words: String, near: [Suggestion]) -> Bool {
        let lower = words.lowercased()
        guard !lower.contains(" ") else { return false }
        return near.contains { $0.kind != .search && $0.kind != .searched && $0.key.hasPrefix(lower) }
    }

    // MARK: - secrets

    /// A guess, and a cautious one: a word lost to a false alarm costs a few
    /// suggestions, a password sent costs the password.
    static func looksSecret(_ words: String) -> Bool {
        let lower = words.lowercased()
        if lower.firstMatch(of: labelled) != nil { return true }
        if lower.firstMatch(of: email) != nil { return true }
        if longestDigitRun(words) >= 9 { return true }
        return words.split(separator: " ").contains { token in
            prefixes.contains { token.hasPrefix($0) } || isKeyLike(token) || isPasswordLike(token)
        }
    }

    /// "password: …", "my pwd is …", "api_key=…".
    nonisolated(unsafe) private static let labelled =
        /\b(password|passwd|passcode|pwd|pin|api[ _-]?key|secret|token)\s*(is\b|:|=)\s*\S/

    nonisolated(unsafe) private static let email = /[^\s@]+@[^\s@]+\.[^\s@]+/

    /// How keys and tokens announce themselves. Only the unmistakable: "sk-"
    /// alone is also SK-II, and "ASIA" is also Asia; the long ones are
    /// caught as long ones.
    private static let prefixes = [
        "sk-ant-", "sk-proj-", "pk_live_", "sk_live_", "rk_live_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
        "github_pat_", "glpat-", "xoxa-", "xoxb-", "xoxp-", "xoxr-", "xoxs-", "AIza", "eyJ", "-----BEGIN",
    ]

    /// Long and unbroken: a hash, a key, a blob. A long word in a language
    /// that makes them has no digits and no capitals after its first letter.
    private static func isKeyLike(_ token: Substring) -> Bool {
        if token.count >= 40 { return true }
        guard token.count >= 20 else { return false }
        return token.contains(where: \.isNumber) || token.dropFirst().contains(where: \.isUppercase)
    }

    /// Mixed-case words with digits, or other long mixtures of character
    /// classes. This errs toward withholding a password-shaped word.
    private static func isPasswordLike(_ token: Substring) -> Bool {
        guard token.count >= 8 else { return false }
        let kinds = [
            token.contains(where: \.isLowercase),
            token.contains(where: \.isUppercase),
            token.contains(where: \.isNumber),
            token.contains { !$0.isLetter && !$0.isNumber },
        ].filter { $0 }.count
        let mixedLettersAndDigits = token.contains(where: \.isLowercase)
            && token.contains(where: \.isUppercase) && token.contains(where: \.isNumber)
        return kinds == 4 || (kinds == 3 && (token.count >= 14 || mixedLettersAndDigits))
    }

    /// The most digits in a row, counting across the spaces, dashes, dots
    /// and brackets that card, phone and identity numbers are written with.
    private static func longestDigitRun(_ words: String) -> Int {
        var longest = 0
        var run = 0
        for character in words {
            if character.isASCII, character.isNumber {
                run += 1
                longest = max(longest, run)
            } else if !" -.()+/".contains(character) {
                run = 0
            }
        }
        return longest
    }
}
