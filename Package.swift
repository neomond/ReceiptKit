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
        // On-device LLM extractor (Foundation Models, iOS 26+) with heuristic fallback.
        .library(name: "ReceiptKitIntelligence", targets: ["ReceiptKitIntelligence"]),
        // Labeled fixture format + scoring metrics, shared by the eval CLI and the demo app.
        .library(name: "ReceiptKitEvaluation", targets: ["ReceiptKitEvaluation"]),
        // `swift run receiptkit-eval Eval/fixtures`
        .executable(name: "receiptkit-eval", targets: ["ReceiptKitEvalCLI"]),
    ],
    targets: [
        .target(name: "ReceiptKit"),
        .target(name: "ReceiptKitUI", dependencies: ["ReceiptKit"]),
        .target(name: "ReceiptKitIntelligence", dependencies: ["ReceiptKit"]),
        .target(name: "ReceiptKitEvaluation", dependencies: ["ReceiptKit"]),
        .executableTarget(
            name: "ReceiptKitEvalCLI",
            dependencies: ["ReceiptKit", "ReceiptKitIntelligence", "ReceiptKitEvaluation"]
        ),
        .testTarget(name: "ReceiptKitTests", dependencies: ["ReceiptKit"]),
        .testTarget(name: "ReceiptKitIntelligenceTests", dependencies: ["ReceiptKit", "ReceiptKitIntelligence"]),
        .testTarget(name: "ReceiptKitEvaluationTests", dependencies: ["ReceiptKit", "ReceiptKitEvaluation"]),
    ]
)
