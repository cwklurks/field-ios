import SwiftUI
import UIKit

/// `-FieldTouchMarks YES`: a ring under every finger, for the video loop in
/// docs/motion.md. The ring goes the moment the finger lifts, pushed to the
/// screen before the app acts on the touch, so in a recording the first frame
/// without it is the tap and the frames after it count the response.
enum TouchMarks {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "FieldTouchMarks") }

    /// A green square in the corner for a moment: marks, in the recording,
    /// the frame a commit made it into.
    static func flag(in window: UIWindow?) {
        guard isOn, let window else { return }
        let square = UIView(frame: CGRect(x: 0, y: window.bounds.height - 12, width: 12, height: 12))
        square.backgroundColor = .systemGreen
        window.addSubview(square)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { square.removeFromSuperview() }
    }

    static func install(in window: UIWindow) {
        guard isOn, !(window.gestureRecognizers ?? []).contains(where: { $0 is Watcher }) else { return }
        window.addGestureRecognizer(Watcher())
    }

    /// Sees every touch and claims none of them.
    private final class Watcher: UIGestureRecognizer {
        private var rings: [UITouch: UIView] = [:]

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let window = view else { return }
            for touch in touches {
                let ring = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
                ring.layer.cornerRadius = 14
                ring.layer.borderWidth = 3
                ring.layer.borderColor = UIColor.systemRed.cgColor
                ring.isUserInteractionEnabled = false
                ring.center = touch.location(in: window)
                window.addSubview(ring)
                rings[touch] = ring
            }
            CATransaction.flush()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let window = view else { return }
            for touch in touches { rings[touch]?.center = touch.location(in: window) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            FieldSurface.log.notice("marks: touch ended \(CACurrentMediaTime())")
            lift(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            lift(touches)
        }

        private func lift(_ touches: Set<UITouch>) {
            for touch in touches { rings.removeValue(forKey: touch)?.removeFromSuperview() }
            CATransaction.flush()
            if rings.isEmpty { state = .failed }
        }

        override func reset() {
            rings.values.forEach { $0.removeFromSuperview() }
            rings = [:]
        }
    }
}

/// Puts the touch marks on whatever window this lands in.
struct TouchMarksInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { TouchMarks.install(in: window) }
        }
    }
}
