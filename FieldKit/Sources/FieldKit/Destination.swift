// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

public enum Destination {
    /// What the field goes to: an address if the text is one, otherwise a search.
    public static func url(for text: String, engine: Engine, custom: String) -> URL? {
        Address.url(from: text) ?? Engine.url(for: text, template: engine.template(custom: custom))
    }
}
