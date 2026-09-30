import Foundation
import SwiftUI
import Testing
import UIKit
@testable import FieldKit
@testable import Field

/// Not a check of logic: Saved's views on screen at a person's pace, for
/// recording on video (docs/motion.md, "The video loop"), how many frames a
/// sheet takes to start moving, and a 500-page list scrolled at a flick's
/// speed while every frame is timed. Runs only when asked, with
/// TEST_RUNNER_SAVED_TOUR=1 (and TEST_RUNNER_SAVED_ROWS for the list's
/// size). In a window of its own over the app. Temporary, like the harness.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SAVED_TOUR"] != nil))
struct SavedTourTests {
    let pause: Duration = .seconds(1.4)

    @Test func tour() async throws {
        let (stage, window) = try await show()
        defer { window.isHidden = true }
        stage.keyboard = true
        try await Task.sleep(for: pause)

        // Save three pages: the sheet rises, a folder is suggested for two.
        for _ in 0..<3 {
            let frames = await framesToMove(window) { stage.save() }
            print("SAVED-SHEET frames to first move: \(frames)")
            #expect(frames <= 2)
            try await Task.sleep(for: pause)
            window.rootViewController?.presentedViewController?.dismiss(animated: true)
            try await Task.sleep(for: pause)
        }
        stage.keyboard = false
        try await Task.sleep(for: pause)

        // The list, all of it and then what's to read.
        for start in [SavedFilter.all, .readLater] {
            let frames = await framesToMove(window) { stage.showList(start) }
            print("SAVED-LIST frames to first move: \(frames)")
            #expect(frames <= 2)
            try await Task.sleep(for: pause)
            window.rootViewController?.presentedViewController?.dismiss(animated: true)
            try await Task.sleep(for: pause)
        }
    }

    /// A flick's speed down the whole list and back, every frame timed.
    @Test func scroll() async throws {
        let rows = Int(ProcessInfo.processInfo.environment["SAVED_ROWS"] ?? "") ?? 500
        let (stage, window) = try await show(seed: rows)
        defer { window.isHidden = true }
        let opening = await framesToMove(window) { stage.showList() }
        print("SAVED-LIST rows=\(rows) frames to first move: \(opening)")
        #expect(opening <= 2)
        try await Task.sleep(for: .seconds(1.5))
        let sheet = try #require(window.rootViewController?.presentedViewController?.view)
        let list = try #require(find(UICollectionView.self, in: sheet))
        let shown = (0..<list.numberOfSections).map(list.numberOfItems).reduce(0, +)
        #expect(shown >= rows)

        let frames = await Flick(list: list, speed: 2_400).run()
        let budget = 1.0 / Double(window.screen.maximumFramesPerSecond)
        let late = frames.filter { $0 > budget * 1.5 }
        let hitch = late.map { $0 - budget }.reduce(0, +)
        let seconds = frames.reduce(0, +)
        print("SAVED-SCROLL rows=\(shown) frames=\(frames.count) late=\(late.count) hitch=\(String(format: "%.1f", hitch * 1000))ms over \(String(format: "%.2f", seconds))s = \(String(format: "%.2f", hitch * 1000 / seconds)) ms/s, worst=\(String(format: "%.1f", (frames.max() ?? 0) * 1000))ms")
        #expect(hitch * 1000 / seconds < 2)
        window.rootViewController?.presentedViewController?.dismiss(animated: true)
        try await Task.sleep(for: .seconds(1))
    }

    // MARK: - helpers

    /// The harness in a window of its own, over the app and key, so the
    /// sheets go up from it.
    private func show(seed: Int = 0) async throws -> (SavedHarnessStage, UIWindow) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let stage = SavedHarnessStage(seed: seed)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .light
        window.tintColor = Palette.UI.ink
        window.rootViewController = SavedHarnessController(stage: stage)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2.5))
        return (stage, window)
    }

    /// Frames from `start` until whatever it presents is seen to move: 1 is
    /// the frame straight after.
    private func framesToMove(_ window: UIWindow, _ start: () -> Void) async -> Int {
        start()
        let watch = Watch(window: window)
        return await watch.run()
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let found = find(type, in: child) { return found }
        }
        return nil
    }
}

/// Counts display frames until the presented sheet's top, as drawn, is
/// above the bottom of the screen.
@MainActor
private final class Watch: NSObject {
    let window: UIWindow
    private var link: CADisplayLink?
    private var frames = 0
    private var done: CheckedContinuation<Int, Never>?

    init(window: UIWindow) { self.window = window }

    func run() async -> Int {
        await withCheckedContinuation { continuation in
            done = continuation
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        frames += 1
        let sheet = window.rootViewController?.presentedViewController?.presentationController?.presentedView
        let top = sheet?.layer.presentation().map { $0.frame.minY } ?? .infinity
        guard top < window.bounds.height - 1 || frames > 60 else { return }
        link.invalidate()
        done?.resume(returning: frames)
        done = nil
    }
}

/// Moves a list by a steady speed each frame, as a finger's flick would,
/// down to the end and back, and hands back how long each frame took.
@MainActor
private final class Flick: NSObject {
    let list: UIScrollView
    let speed: CGFloat
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames: [Double] = []
    private var direction: CGFloat = 1
    private var done: CheckedContinuation<[Double], Never>?

    init(list: UIScrollView, speed: CGFloat) {
        self.list = list
        self.speed = speed
    }

    func run() async -> [Double] {
        await withCheckedContinuation { continuation in
            done = continuation
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { frames.append(link.timestamp - last) }
        last = link.timestamp
        let step = speed * CGFloat(link.targetTimestamp - link.timestamp) * direction
        let bottom = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        let top = -list.adjustedContentInset.top
        var y = list.contentOffset.y + step
        if y >= bottom {
            y = bottom
            direction = -1
        } else if y <= top, direction < 0 {
            y = top
            link.invalidate()
            done?.resume(returning: frames)
            done = nil
        }
        list.contentOffset.y = y
    }
}
