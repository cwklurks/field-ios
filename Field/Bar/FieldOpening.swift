import UIKit
import os

/// The `field.open` interval: begun by the bar at the tap on the address,
/// ended by the omnibox once its field is focused and the keyboard is up.
/// With a hardware keyboard no software one comes, so if none has started
/// up after `patience`, the interval ends there.
enum FieldOpening {
    static let patience: Duration = .seconds(0.6)

    private static var state: OSSignpostIntervalState?
    /// Which opening is current, so a late timer can't end a newer one.
    private static var opening = 0
    private static var keyboardComing = false
    private static var watcher: (any NSObjectProtocol)?

    static func begin() {
        end()
        watchKeyboard()
        opening += 1
        keyboardComing = false
        state = Signpost.log.beginAnimationInterval(Signpost.fieldOpen)
        let this = opening
        Task {
            try? await Task.sleep(for: patience)
            guard opening == this, !keyboardComing else { return }
            end()
        }
    }

    /// Safe to call when nothing was begun: the field also opens on its own
    /// on a blank tab.
    static func end() {
        guard let state else { return }
        Signpost.log.endInterval(Signpost.fieldOpen, state)
        self.state = nil
    }

    private static func watchKeyboard() {
        guard watcher == nil else { return }
        watcher = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { keyboardComing = true }
        }
    }
}
