import FieldKit
import SwiftUI

/// Private's two choices, kept with the rest of Settings. They say how
/// Private behaves, never whether it was used.
struct PrivateSettings {
    static let awayKey = "private.away"
    /// Minutes; 0 or none is never.
    static let wipeAfterKey = "private.wipeAfter"
    static let wipeChoices = [0, 5, 15, 60]

    var away: PrivateLock.Away
    var wipeAfter: TimeInterval?

    init(_ defaults: UserDefaults = .standard) {
        away = defaults.string(forKey: Self.awayKey).flatMap(PrivateLock.Away.init(rawValue:)) ?? .lock
        let minutes = defaults.integer(forKey: Self.wipeAfterKey)
        wipeAfter = minutes > 0 ? TimeInterval(minutes * 60) : nil
    }
}

/// Settings › Private: what leaving does, and how long it keeps.
struct PrivateSettingsSection: View {
    @AppStorage(PrivateSettings.awayKey) private var away: PrivateLock.Away = .lock
    @AppStorage(PrivateSettings.wipeAfterKey) private var wipeAfter = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When you leave").ramp(.caption).foregroundStyle(Palette.muted)
            Segmented(options: [(PrivateLock.Away.lock, "Lock"), (.wipe, "Wipe")], selection: $away)
            Text(away == .lock ? "Face ID opens it again." : "Everything in it is gone.")
                .ramp(.caption).foregroundStyle(Palette.muted)
            Text("Wipe when away for").ramp(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
            Segmented(options: PrivateSettings.wipeChoices.map { ($0, Self.title($0)) }, selection: $wipeAfter)
            // Use the same presenter as Private's welcome page.
            Button(action: PrivateLimits.present) {
                HStack {
                    Text("What Private can't do").ramp(.row)
                    Spacer()
                    Image(systemName: "chevron.right").ramp(.caption).foregroundStyle(Palette.muted)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    static func title(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Never"
        case 60: "1 hour"
        default: "\(minutes) min"
        }
    }
}
