import CoreGraphics
import Foundation

/// The SDK's entry point.
///
/// ```swift
/// let scanner = ReceiptScanner()
/// let result = try await scanner.scan(cgImage)
/// if result.needsReview { /* show a confirm screen */ }
/// ```
public struct ReceiptScanner: Sendable {
    public let configuration: ReceiptKitConfiguration
    private let recognizer: any TextRecognizing
    private let extractor: any ReceiptExtracting

    public init(
        configuration: ReceiptKitConfiguration = .default,
        recognizer: any TextRecognizing = VisionTextRecognizer(),
        extractor: any ReceiptExtracting = HeuristicReceiptExtractor()
    ) {
        self.configuration = configuration
        self.recognizer = recognizer
        self.extractor = extractor
    }

    public func scan(_ image: CGImage) async throws -> ReceiptScanResult {
        let lines = try await recognizer.recognizeText(in: image, configuration: configuration)
        try Task.checkCancellation()

        guard lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw ReceiptScanError.noTextFound
        }

        let receipt = try await extractor.extract(from: lines, configuration: configuration)
        let warnings = ReceiptValidator.warnings(for: receipt, lines: lines, configuration: configuration)
        return ReceiptScanResult(receipt: receipt, warnings: warnings, recognizedLines: lines)
    }
}
