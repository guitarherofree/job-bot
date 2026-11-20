// swift-tools-version:5.9
//
// Job Bot: a private macOS app for tailoring resumes and cover letters to job postings.
//
// The package has these parts:
//   • JobBotCore: pure Swift (Foundation only). Profiles, job parsing, matching with evidence,
//     tailoring suggestions, cover letters, DOCX export, versions. Builds and tests anywhere.
//   • JobBotRender: macOS only. Paginated PDF output for resumes and cover letters.
//   • JobBotUI: macOS only. The SwiftUI interface and app model.
//   • JobBot: the macOS app (a thin @main around JobBotUI).
import PackageDescription

var products: [Product] = [
    .library(name: "JobBotCore", targets: ["JobBotCore"]),
]

var targets: [Target] = [
    .target(
        name: "JobBotCore",
        path: "Sources/JobBotCore"
    ),
    .testTarget(
        name: "JobBotCoreTests",
        dependencies: ["JobBotCore"],
        path: "Tests/JobBotCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "JobBot", targets: ["JobBot"]))
targets.append(contentsOf: [
    .target(
        name: "JobBotRender",
        dependencies: ["JobBotCore"],
        path: "Sources/JobBotRender"
    ),
    .target(
        name: "JobBotUI",
        dependencies: ["JobBotCore", "JobBotRender"],
        path: "Sources/JobBotUI"
    ),
    .executableTarget(
        name: "JobBot",
        dependencies: ["JobBotUI"],
        path: "Sources/JobBot"
    ),
    .testTarget(
        name: "JobBotMacTests",
        dependencies: ["JobBotCore", "JobBotRender", "JobBotUI"],
        path: "Tests/JobBotMacTests"
    ),
])
#endif

let package = Package(
    name: "JobBot",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
