import Foundation
import WebKit

@main
struct Bench {
    @MainActor static func main() async {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WKContentRuleListStore(url: dir)!
        for path in CommandLine.arguments.dropFirst(2) {
            let json = try! String(contentsOfFile: path, encoding: .utf8)
            let id = (path as NSString).lastPathComponent
            let t0 = Date()
            do {
                _ = try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json)
                let t1 = Date()
                _ = try await store.contentRuleList(forIdentifier: id)
                let t2 = Date()
                print(String(format: "%@ compile %.2fs lookup %.1fms", id, t1.timeIntervalSince(t0), t2.timeIntervalSince(t1)*1000))
            } catch {
                print("\(id) error \(error)")
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files {
            let a = try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(f).path)
            print(f, (a?[.size] as? Int) ?? 0)
        }
    }
}
