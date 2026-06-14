// swift-tools-version:5.9
import PackageDescription

// A lightweight SwiftPM package that compiles the app's pure, Foundation-only
// logic (SQLTerminal/Core) as a `SQLCore` library so it can be unit-tested with
// `swift test` — without building the whole macOS app. The same source files are
// also part of the Xcode app target (via its synchronized group), so there is a
// single source of truth; this manifest only adds a test entry point.
//
//   swift test
//
let package = Package(
    name: "SQLCore",
    targets: [
        .target(name: "SQLCore", path: "SQLTerminal/Core"),
        .testTarget(name: "SQLCoreTests", dependencies: ["SQLCore"], path: "Tests/SQLCoreTests"),
    ]
)
