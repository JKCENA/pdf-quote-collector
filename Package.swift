// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PDFQuoteCollector",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PDFQuoteCollectorCore", targets: ["PDFQuoteCollectorCore"]),
        .executable(name: "PDFQuoteCollector", targets: ["PDFQuoteCollectorApp"]),
        .executable(name: "PDFQuoteCollectorTests", targets: ["PDFQuoteCollectorTests"])
    ],
    targets: [
        .target(name: "PDFQuoteCollectorCore"),
        .executableTarget(
            name: "PDFQuoteCollectorApp",
            dependencies: ["PDFQuoteCollectorCore"]
        ),
        .executableTarget(
            name: "PDFQuoteCollectorTests",
            dependencies: ["PDFQuoteCollectorCore"],
            path: "Sources/PDFQuoteCollectorTests"
        )
    ]
)
