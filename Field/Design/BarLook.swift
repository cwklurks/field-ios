import SwiftUI

/// The bar's two looks, until one is chosen for good on a real phone: Liquid
/// Glass, or the Mac's solid raised surface. Stored in UserDefaults "bar.look".
enum BarLook: String, CaseIterable, Identifiable {
    case glass, solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "Glass"
        case .solid: return "Solid"
        }
    }
}
