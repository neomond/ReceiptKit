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
