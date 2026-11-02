import Foundation
import ReceiptKit

/// How one prediction compares to its label.
public struct ReceiptScore: Sendable, Equatable {
    public var merchant: Bool
    public var date: Bool
    public var total: Bool
    public var currency: Bool
    public var matchedItems: Int
    public var predictedItems: Int
    public var expectedItems: Int

    public var itemsExact: Bool {
        matchedItems == predictedItems && matchedItems == expectedItems
    }

    public var isFullyCorrect: Bool {
        merchant && date && total && currency && itemsExact
    }
}

public enum ReceiptScorer {
    /// Minimum name similarity for two items with the same amount to count as a match.
    /// Tolerates OCR typos ("Cr0issant") without matching unrelated products.
    public static let itemNameThreshold = 0.5

    public static func score(_ predicted: Receipt, against expected: ExpectedReceipt) -> ReceiptScore {
        ReceiptScore(
            merchant: merchantMatches(predicted.merchant, expected.merchant),
            date: dateMatches(predicted.date, expected.date),
            total: amountMatches(predicted.total?.amount, expected.total),
            currency: predicted.currencyCode.uppercased() == expected.currency.uppercased(),
            matchedItems: matchedItemCount(predicted: predicted.items, expected: expected.items),
            predictedItems: predicted.items.count,
            expectedItems: expected.items.count
        )
    }

    // MARK: - Fields

    /// Both missing is correct; a value where the label has none is a hallucination.
    /// "BRAVO SUPERMARKET" matches the label "Bravo".
    static func merchantMatches(_ predicted: String?, _ expected: String?) -> Bool {
        switch (predicted.map(normalize), expected.map(normalize)) {
        case (nil, nil): return true
        case let (p?, e?):
            if p == e { return true }
            return min(p.count, e.count) >= 3 && (p.contains(e) || e.contains(p))
        default: return false
        }
    }

    static func dateMatches(_ predicted: Date?, _ expected: String?) -> Bool {
        switch (predicted, expected) {
        case (nil, nil): return true
        case let (p?, e?): return FixtureFormat.dateString(p) == e
        default: return false
        }
    }

    static func amountMatches(_ predicted: Decimal?, _ expected: String?) -> Bool {
        switch (predicted, expected.flatMap(FixtureFormat.amount)) {
        case (nil, nil): return true
        case let (p?, e?): return p == e
        default: return false
        }
    }

    // MARK: - Items

    /// Greedy one-to-one matching: same amount and similar name.
    static func matchedItemCount(predicted: [ReceiptLineItem], expected: [ExpectedItem]) -> Int {
        var available = Array(predicted.indices)
        var matched = 0

        for item in expected {
            guard let amount = FixtureFormat.amount(item.total) else { continue }
            let expectedName = normalize(item.name)

            let candidate = available.firstIndex { index in
                predicted[index].total.amount == amount
                    && nameSimilarity(normalize(predicted[index].name), expectedName) >= itemNameThreshold
            }
            if let candidate {
                available.remove(at: candidate)
                matched += 1
            }
        }
        return matched
    }

    /// Sørensen–Dice coefficient on character bigrams, 0...1.
    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if min(a.count, b.count) >= 3, a.contains(b) || b.contains(a) { return 1 }

        let bigramsA = bigrams(a)
        let bigramsB = bigrams(b)
        guard !bigramsA.isEmpty, !bigramsB.isEmpty else { return 0 }

        var remaining = bigramsB
        var shared = 0
        for bigram in bigramsA {
            if let index = remaining.firstIndex(of: bigram) {
                remaining.remove(at: index)
                shared += 1
            }
        }
        return Double(2 * shared) / Double(bigramsA.count + bigramsB.count)
    }

    private static func bigrams(_ string: String) -> [String] {
        let characters = Array(string)
        guard characters.count >= 2 else { return [] }
        return (0..<(characters.count - 1)).map { String(characters[$0...$0 + 1]) }
    }

    /// Letters that are separate letters in Azerbaijani/Turkish, not accented
    /// variants, so diacritic folding leaves them alone. OCR and the LLM often
    /// write the plain Latin letter instead ("Bakilift" for "Bakılift").
    private static let letterFolding: [Character: Character] = ["ı": "i", "İ": "i", "ə": "e", "Ə": "e"]

    /// Lower-case, diacritics folded, letters and digits only.
    static func normalize(_ string: String) -> String {
        String(string.map { letterFolding[$0] ?? $0 })
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
