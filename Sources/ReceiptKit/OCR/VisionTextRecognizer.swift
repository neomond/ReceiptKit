import CoreGraphics
import Foundation
import Vision

/// Default OCR engine, built on the Swift-native Vision API (iOS 18+).
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognizeText(
        in image: CGImage,
        configuration: ReceiptKitConfiguration
    ) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" prices and codes into words; keep it off for receipts.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = configuration.recognitionLanguages.map { Locale.Language(identifier: $0) }

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            throw ReceiptScanError.recognitionFailed(error.localizedDescription)
        }

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox.cgRect
            )
        }
    }
}
