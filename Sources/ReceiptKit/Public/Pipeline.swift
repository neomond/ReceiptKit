import CoreGraphics
import Foundation

/// One piece of text found by OCR.
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    public var confidence: Float
    /// Normalized coordinates (0...1), origin at the bottom-left, as Vision reports them.
    /// `.zero` means "unknown"; lines are then kept in the order given.
    public var boundingBox: CGRect

    public init(text: String, confidence: Float = 1, boundingBox: CGRect = .zero) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Step 1 of the pipeline: image → text.
/// Public so hosts and tests can swap in another OCR engine.
public protocol TextRecognizing: Sendable {
    func recognizeText(in image: CGImage, configuration: ReceiptKitConfiguration) async throws -> [RecognizedLine]
}

/// Step 2 of the pipeline: text → structured receipt.
/// Public so a host can plug in an on-device LLM extractor (Foundation Models)
/// and fall back to `HeuristicReceiptExtractor` when it isn't available.
public protocol ReceiptExtracting: Sendable {
    func extract(from lines: [RecognizedLine], configuration: ReceiptKitConfiguration) async throws -> Receipt
}

/// Reading-order view of OCR output, for extractors that work on text rows
/// (e.g. an LLM prompt) rather than on raw observations.
public enum ReceiptLayout {
    /// Merges observations printed on the same row (item name + price) and
    /// returns rows top to bottom.
    public static func rows(from lines: [RecognizedLine], minimumConfidence: Float = 0) -> [String] {
        RowGrouper.rows(from: lines, minimumConfidence: minimumConfidence)
    }
}

/// Tries `primary`; if it throws (model unavailable, context window exceeded,
/// generation error), uses `fallback`. Cancellation is never swallowed.
public struct FallbackReceiptExtractor: ReceiptExtracting {
    public let primary: any ReceiptExtracting
    public let fallback: any ReceiptExtracting

    public init(primary: any ReceiptExtracting, fallback: any ReceiptExtracting) {
        self.primary = primary
        self.fallback = fallback
    }

    public func extract(from lines: [RecognizedLine], configuration: ReceiptKitConfiguration) async throws -> Receipt {
        do {
            return try await primary.extract(from: lines, configuration: configuration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return try await fallback.extract(from: lines, configuration: configuration)
        }
    }
}
