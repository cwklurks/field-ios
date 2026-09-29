import UIKit
import os

/// Whether the software keyboard is on screen, and a way to load it before
/// it's first wanted.
enum Keyboard {
    private(set) static var up = false
    /// Some keyboard has come up in this process, so it's loaded.
    private(set) static var loaded = false
    /// Set while `warm` runs: the keyboard notices then are the warm-up's.
    private(set) static var warming = false
    private static var watching = false

    static func watch() {
        guard !watching else { return }
        watching = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                up = true
                loaded = true
            }
        }
        center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { up = false }
        }
    }

    /// Loads the keyboard without showing it. The first focus in a process
    /// holds the main thread for about half a second on the phone, most of
    /// it iOS loading its keyboard; later ones cost a fraction of that. So
    /// once the page is up and nothing is moving, a hidden field with the
    /// field's own keyboard takes focus and gives it up in the same turn,
    /// before anything is drawn, and the tap on the address then finds the
    /// keyboard loaded.
    static func warm(in window: UIWindow) {
        watch()
        guard !loaded, !warming else { return }
        loaded = true
        let field = UITextField(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        AddressField.keyboard(for: field)
        field.alpha = 0
        field.isAccessibilityElement = false
        window.addSubview(field)
        let state = Signpost.log.beginInterval("keyboard.warm")
        warming = true
        field.becomeFirstResponder()
        field.resignFirstResponder()
        warming = false
        Signpost.log.endInterval("keyboard.warm", state)
        field.removeFromSuperview()
    }
}
