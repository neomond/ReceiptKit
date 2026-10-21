// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReceiptKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        // Core SDK: OCR + parsing + validation. No UI dependency.
        .library(name: "ReceiptKit", targets: ["ReceiptKit"]),
        // Optional drop-in UIKit capture screen built on top of the core.
        .library(name: "ReceiptKitUI", targets: ["ReceiptKitUI"]),
    ],
    targets: [
        .target(name: "ReceiptKit"),
        .target(name: "ReceiptKitUI", dependencies: ["ReceiptKit"]),
        .testTarget(name: "ReceiptKitTests", dependencies: ["ReceiptKit"]),
    ]
)
