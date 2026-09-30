// swift-tools-version: 6.2
import PackageDescription

// The logic Field shares no UI with: address parsing, search engines, history
// ranking and later the navigation guard. Foundation only, so `swift test`
// runs on the Mac in seconds without a simulator.
let package = Package(
    name: "FieldKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "FieldKit", targets: ["FieldKit"])],
    targets: [
        .target(name: "FieldKit", exclude: ["Guard/README.md"], resources: [.process("Guard/Rules")]),
        .testTarget(name: "FieldKitTests", dependencies: ["FieldKit"]),
    ]
)
