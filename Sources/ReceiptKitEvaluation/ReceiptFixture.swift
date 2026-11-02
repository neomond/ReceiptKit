import CoreGraphics
import Foundation
import ReceiptKit

/// One labeled receipt: the OCR output plus the correct answer.
///
/// Fixtures store OCR text, not images, so evaluation is deterministic, runs
/// in seconds on a Mac, and compares extractors on exactly the same input.
/// Amounts and dates are strings so the JSON is easy to correct by hand.
public struct ReceiptFixture: Codable, Sendable, Equatable {
    public var id: String
    public var notes: String?
    public var lines: [FixtureLine]
    public var expected: ExpectedReceipt

    public init(id: String, notes: String? = nil, lines: [FixtureLine], expected: ExpectedReceipt) {
        self.id = id
        self.notes = notes
        self.lines = lines
        self.expected = expected
    }

    public var recognizedLines: [RecognizedLine] {
        lines.map(\.recognizedLine)
    }
}

public struct FixtureLine: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Float
    /// Normalized [x, y, width, height], origin bottom-left (Vision convention).
    public var box: [Double]?

    public init(text: String, confidence: Float = 1, box: [Double]? = nil) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }

    public init(_ line: RecognizedLine) {
        let rect = line.boundingBox
        let round: (CGFloat) -> Double = { (Double($0) * 10_000).rounded() / 10_000 }
        self.init(
            text: line.text,
            confidence: (line.confidence * 1000).rounded() / 1000,
            box: rect.isEmpty ? nil : [round(rect.minX), round(rect.minY), round(rect.width), round(rect.height)]
        )
    }

    public var recognizedLine: RecognizedLine {
        var rect = CGRect.zero
        if let box, box.count == 4 {
            rect = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        }
        return RecognizedLine(text: text, confidence: confidence, boundingBox: rect)
    }
}

public struct ExpectedReceipt: Codable, Sendable, Equatable {
    public var merchant: String?
    /// yyyy-MM-dd
    public var date: String?
    public var currency: String
    /// Decimal string, e.g. "11.20".
    public var total: String?
    public var items: [ExpectedItem]

    public init(merchant: String?, date: String?, currency: String, total: String?, items: [ExpectedItem]) {
        self.merchant = merchant
        self.date = date
        self.currency = currency
        self.total = total
        self.items = items
    }
}

public struct ExpectedItem: Codable, Sendable, Equatable {
    public var name: String
    public var quantity: Int?
    /// Line total as a decimal string, negative for discounts.
    public var total: String

    public init(name: String, quantity: Int? = nil, total: String) {
        self.name = name
        self.quantity = quantity
        self.total = total
    }
}

// MARK: - Drafting labels from a scan

extension ReceiptFixture {
    /// A fixture whose `expected` block is pre-filled from the scanner's own
    /// output. It is a draft: correct the `expected` block by hand before using
    /// it, otherwise the evaluation just measures agreement with itself.
    public init(draftFrom result: ReceiptScanResult, id: String, notes: String? = "DRAFT: verify expected against the paper receipt") {
        self.init(
            id: id,
            notes: notes,
            lines: result.recognizedLines.map(FixtureLine.init),
            expected: ExpectedReceipt(draftFrom: result.receipt)
        )
    }
}

extension ExpectedReceipt {
    public init(draftFrom receipt: Receipt) {
        self.init(
            merchant: receipt.merchant,
            date: receipt.date.map(FixtureFormat.dateString),
            currency: receipt.currencyCode,
            total: receipt.total.map { FixtureFormat.amountString($0.amount) },
            items: receipt.items.map {
                ExpectedItem(name: $0.name, quantity: $0.quantity, total: FixtureFormat.amountString($0.total.amount))
            }
        )
    }
}

public enum FixtureFormat {
    static let posix = Locale(identifier: "en_US_POSIX")

    public static func amountString(_ amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let string = NSDecimalNumber(decimal: rounded).description(withLocale: posix)
        // NSDecimalNumber drops trailing zeros ("7"); pad to cents ("7.00").
        guard let dot = string.firstIndex(of: ".") else { return string + ".00" }
        let decimals = string.distance(from: dot, to: string.endIndex) - 1
        return decimals == 1 ? string + "0" : string
    }

    public static func amount(_ string: String) -> Decimal? {
        Decimal(string: string.trimmingCharacters(in: .whitespaces), locale: posix)
    }

    public static func dateString(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted keys put "expected" first: the part you edit is at the top of the file.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func loadFixtures(in directory: URL) throws -> [ReceiptFixture] {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        return try files.map { url in
            do {
                return try decoder.decode(ReceiptFixture.self, from: Data(contentsOf: url))
            } catch {
                throw FixtureLoadingError.invalidFixture(file: url.lastPathComponent, reason: String(describing: error))
            }
        }
    }
}

public enum FixtureLoadingError: Error, CustomStringConvertible {
    case invalidFixture(file: String, reason: String)

    public var description: String {
        switch self {
        case let .invalidFixture(file, reason): "Could not read \(file): \(reason)"
        }
    }
}
