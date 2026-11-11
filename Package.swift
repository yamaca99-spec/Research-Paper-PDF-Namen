// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PaperRenamer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PaperRenamer", targets: ["PaperRenamer"]),
    ],
    targets: [
        // Platform-independent logic: metadata lookup, heuristics, file naming.
        .target(name: "PaperRenamerCore"),
        // The macOS app (SwiftUI + PDFKit).
        .executableTarget(
            name: "PaperRenamer",
            dependencies: ["PaperRenamerCore"]
        ),
        .testTarget(
            name: "PaperRenamerCoreTests",
            dependencies: ["PaperRenamerCore"]
        ),
    ]
)
