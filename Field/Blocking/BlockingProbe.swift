import Foundation
import WebKit

/// `-FieldBlockingProbe YES`: prints how long blocking's launch work takes,
/// how long the main thread went without running while a list compiled,
/// what `apply` costs, and the app's memory footprint. For measuring, never
/// on in a normal launch.
@MainActor final class BlockingProbe {
    /// Taken from the launch arguments only, so no stored setting can turn it on.
    static var isOn: Bool {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        return arguments["FieldBlockingProbe"] != nil && UserDefaults.standard.bool(forKey: "FieldBlockingProbe")
    }

    static func start() -> BlockingProbe? {
        guard isOn else { return nil }
        let probe = BlockingProbe()
        probe.say("prepare, footprint \(Self.footprint())")
        return probe
    }

    private var timer: Timer?
    private var tick = ContinuousClock.now
    private var longest: Duration = .zero
    private var watching = ContinuousClock.now
    /// Each gap over a 120 Hz frame: when it started, since `watchMainThread`, and how long.
    private var stalls: [(at: Duration, length: Duration)] = []

    func note(_ what: String, since start: ContinuousClock.Instant) {
        say("\(what): \(Self.ms(.now - start))")
    }

    /// A 1 ms timer on the main run loop; the longest gap between its fires
    /// is the longest the main thread was held.
    func watchMainThread() {
        longest = .zero
        stalls = []
        tick = .now
        watching = tick
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = ContinuousClock.now
                let gap = now - self.tick
                self.longest = max(self.longest, gap)
                if gap > .milliseconds(8) { self.stalls.append((self.tick - self.watching, gap)) }
                self.tick = now
            }
        }
    }

    func noteMainThread(while what: String) {
        timer?.invalidate()
        timer = nil
        say("  longest main-thread gap while \(what): \(Self.ms(longest)), footprint \(Self.footprint())")
        for stall in stalls { say("  held \(Self.ms(stall.length)) at +\(Self.ms(stall.at))") }
    }

    func finish(removed: [String], measuring blocking: ContentBlocking?) {
        say("ready: \(blocking != nil), removed stale: \(removed), footprint \(Self.footprint())")
        guard let blocking else { return }
        // A controller on a real web view, as a tab's is.
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let controller = web.configuration.userContentController
        let host = "probe.invalid"
        var on: [Duration] = [], same: [Duration] = [], off: [Duration] = []
        for _ in 0..<50 {
            var start = ContinuousClock.now
            blocking.apply(to: controller, host: host)
            on.append(.now - start)
            start = .now
            blocking.apply(to: controller, host: host)
            same.append(.now - start)
            blocking.setShield(false, for: host)
            start = .now
            blocking.apply(to: controller, host: host)
            off.append(.now - start)
            blocking.setShield(true, for: host)
        }
        func summary(_ d: [Duration]) -> String {
            "mean \(Self.ms(d.reduce(.zero, +) / d.count)), max \(Self.ms(d.max() ?? .zero))"
        }
        say("apply, lists on: \(summary(on)); unchanged: \(summary(same)); lists off: \(summary(off))")
    }

    private func say(_ line: String) {
        print("[FieldBlockingProbe] \(line)")
        ContentBlocking.log.notice("\(line, privacy: .public)")
    }

    private static func ms(_ d: Duration) -> String {
        let (s, atto) = d.components
        return String(format: "%.3f ms", Double(s) * 1000 + Double(atto) / 1e15)
    }

    /// The app's physical footprint now and at its peak, as jetsam counts it.
    private static func footprint() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "unknown" }
        return "\(info.phys_footprint >> 20) MB (peak \(info.ledger_phys_footprint_peak >> 20) MB)"
    }
}
