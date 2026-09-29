// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// Light, dark, or the phone's own: the one choice that colours everything.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// What the app is told to be. Nothing, for "system": the app then
    /// follows the phone, and changes with it.
    var scheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
