import SwiftUI
import UIKit
import os

/// `-FieldBaseline YES`: a control for the perf tests. A bare UITextField on
/// ground with the field's keyboard, and nothing else: no bar, no omnibox, no
/// suggestions. It takes focus on launch as a blank tab's field does, and
/// emits `launch.fieldReady` and `field.keystroke` the same way, so what it
/// measures is what the system keyboard costs on its own.
enum Baseline {
    /// Taken from the launch arguments only, so no stored setting can turn it on.
    nonisolated static var isOn: Bool {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments["FieldBaseline"] != nil else { return false }
        return UserDefaults.standard.bool(forKey: "FieldBaseline")
    }
}

struct BaselineView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.ground.ignoresSafeArea()
            BaselineField()
                .frame(height: 50)
                .padding(.horizontal, Bar.margin + 18)
                .padding(.bottom, 8)
        }
    }
}

private struct BaselineField: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = .systemFont(ofSize: Ramp.field.size)
        field.textColor = Palette.UI.ink
        field.placeholder = "Search or enter an address"
        AddressField.keyboard(for: field)
        field.accessibilityIdentifier = "field"
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.delegate = context.coordinator
        // The turn after the first frame, then the next frame: when a blank
        // tab's field takes focus.
        DispatchQueue.main.async {
            NextFrame.run { field.becomeFirstResponder() }
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {}

    final class Coordinator: NSObject, UITextFieldDelegate {
        private var keystrokes: [OSSignpostIntervalState] = []
        private var commit: CFRunLoopObserver?
        private var ready = false

        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard !ready else { return }
            ready = true
            Signpost.log.emitEvent(Signpost.fieldReady)
        }

        /// As the field's own: from the text changing to the commit that shows it.
        @objc func changed() {
            keystrokes.append(Signpost.log.beginInterval(Signpost.keystroke, id: Signpost.log.makeSignpostID()))
            guard commit == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(
                nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
            ) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.drawn() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            commit = observer
        }

        private func drawn() {
            for state in keystrokes { Signpost.log.endInterval(Signpost.keystroke, state) }
            keystrokes = []
            if let commit { CFRunLoopObserverInvalidate(commit) }
            commit = nil
        }
    }
}
