import Foundation
import FieldKit

/// What was open last time, kept in session.json next to history.json: read
/// once at launch, saved a moment after a change (as on the Mac) through one
/// actor, and flushed when the app goes to the background.
@MainActor final class SessionStore {
    /// Nil when there's nothing to keep: the perf tests' made-up tabs.
    let file: SessionFile?
    private let wait: Duration
    /// Until a read works, nothing is saved: a file that couldn't be read
    /// (a protected one, before first unlock) isn't an empty session.
    private var readable = false
    private var shape: (() -> Session.Shape)?
    private var pending: Task<Void, Never>?
    /// Counts saves, so the file can drop an older one arriving late.
    private var generation = 0

    init(directory: URL?, wait: Duration = .seconds(1.2)) {
        file = directory.map { SessionFile(url: $0.appendingPathComponent("session.json")) }
        self.wait = wait
    }

    /// Nil if the file is there but can't be read yet. Small enough to read
    /// before the first frame, so the bar's first frame already shows the
    /// right tab.
    func read() -> Session.Shape? {
        guard let file else {
            readable = false
            return Session.Shape()
        }
        guard let shape = try? Session.Shape.load(from: file.url) else { return nil }
        readable = true
        return shape
    }

    /// Something the session keeps has changed. `shape` is asked for when the
    /// save happens, so a burst of changes is one save of the latest.
    func changed(_ shape: @escaping () -> Session.Shape) {
        self.shape = shape
        guard readable, pending == nil else { return }
        pending = Task { [weak self, wait] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    func flush() async {
        pending?.cancel()
        await save()
    }

    private func save() async {
        pending = nil
        guard readable, let file, let shape = shape?() else { return }
        generation += 1
        await file.write(shape, generation: generation)
    }
}

/// session.json, written one save at a time and never on the main thread.
/// A save older than the last one written is dropped.
actor SessionFile {
    let url: URL
    private var written = 0
    private(set) var writes = 0

    init(url: URL) { self.url = url }

    func write(_ shape: Session.Shape, generation: Int) {
        guard generation > written else { return }
        try? shape.save(to: url)
        written = generation
        writes += 1
    }
}
