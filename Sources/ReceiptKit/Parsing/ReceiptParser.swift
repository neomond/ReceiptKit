import Foundation

/// Rule-based extractor. Fast, offline, deterministic, and the baseline every
/// smarter extractor (Core ML, Foundation Models) gets compared against.
public struct HeuristicReceiptExtractor: ReceiptExtracting {
    public init() {}

    public func extract(from lines: [RecognizedLine], configuration: ReceiptKitConfiguration) async throws -> Receipt {
        let rows = RowGrouper.rows(from: lines, minimumConfidence: configuration.minimumLineConfidence)
        return ReceiptParser(configuration: configuration).parse(rows: rows)
    }
}

/// Pure function from text rows to a `Receipt`. No Vision, no async: easy to unit test.
struct ReceiptParser {
    let configuration: ReceiptKitConfiguration

    private static let totalExclusions = ["subtotal", "sub total", "sub-total", "tax", "vat", "ədv", "ндс"]

    private static let currencyMarkers: [(marker: String, code: String)] = [
        ("₼", "AZN"), ("AZN", "AZN"), ("£", "GBP"), ("GBP", "GBP"),
        ("€", "EUR"), ("EUR", "EUR"), ("₽", "RUB"), ("RUB", "RUB"),
        ("$", "USD"), ("USD", "USD"),
    ]

    func parse(rows: [String]) -> Receipt {
        let currency = detectCurrency(in: rows) ?? configuration.defaultCurrencyCode
        let date = rows.lazy.compactMap(DateParser.date(in:)).first

        let totalIndex = rows.firstIndex(where: isTotalRow)
        let total = totalIndex.flatMap { totalAmount(at: $0, in: rows) }
            .map { Money(amount: $0, currencyCode: currency) }

        let merchantIndex = rows.prefix(3).firstIndex(where: isMerchantCandidate)
        let merchant = merchantIndex.map { rows[$0] }

        let itemRange = 0..<(totalIndex ?? rows.count)
        let items = itemRange
            .filter { $0 != merchantIndex }
            .compactMap { lineItem(from: rows[$0], currency: currency) }

        return Receipt(merchant: merchant, date: date, items: items, total: total, currencyCode: currency)
    }

    // MARK: - Total

    private func isTotalRow(_ row: String) -> Bool {
        containsKeyword(row, configuration.totalKeywords) && !containsKeyword(row, Self.totalExclusions)
    }

    /// Printed on the same row ("TOTAL 11.20") or on the next one.
    private func totalAmount(at index: Int, in rows: [String]) -> Decimal? {
        if let sameRow = amounts(in: rows[index]).last { return sameRow.value }
        guard rows.indices.contains(index + 1) else { return nil }
        return amounts(in: rows[index + 1]).first?.value
    }

    // MARK: - Merchant

    private func isMerchantCandidate(_ row: String) -> Bool {
        row.filter(\.isLetter).count >= 2
            && amounts(in: row).isEmpty
            && DateParser.date(in: row) == nil
            && !containsKeyword(row, configuration.totalKeywords + configuration.nonItemKeywords)
    }

    // MARK: - Line items

    private func lineItem(from row: String, currency: String) -> ReceiptLineItem? {
        guard DateParser.date(in: row) == nil,
              !containsKeyword(row, configuration.nonItemKeywords + configuration.totalKeywords)
        else { return nil }

        // Match ranges must index the same string they were found in.
        let text = DateParser.removingDates(from: row)
        let matches = AmountParser.matches(in: text)
        guard let first = matches.first, let last = matches.last else { return nil }

        // Name is whatever precedes the first amount: "Latte 2 x 3.50 7.00" → "Latte 2 x".
        var name = String(text[..<first.range.lowerBound])
        var quantity = 1

        if let match = name.firstMatch(of: /(\d+)\s*[xX×*]\s*$/) {        // "Latte 2 x"
            quantity = Int(match.output.1) ?? 1
            name.removeSubrange(match.range)
        } else if let match = name.firstMatch(of: /^\s*(\d+)\s*[xX×*]\s*/) { // "2 x Latte"
            quantity = Int(match.output.1) ?? 1
            name.removeSubrange(match.range)
        }

        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        guard name.contains(where: \.isLetter) else { return nil }

        return ReceiptLineItem(name: name, quantity: quantity, total: Money(amount: last.value, currencyCode: currency))
    }

    // MARK: - Helpers

    /// Amounts in a row, ignoring digits that belong to a date.
    private func amounts(in row: String) -> [AmountMatch] {
        AmountParser.matches(in: DateParser.removingDates(from: row))
    }

    private func detectCurrency(in rows: [String]) -> String? {
        let text = " " + rows.joined(separator: " ").uppercased() + " "
        return Self.currencyMarkers.first {
            $0.marker.count == 1 ? text.contains($0.marker) : containsWord(text, $0.marker)
        }?.code
    }

    /// Whole-word match, so "card" doesn't fire on "cardamom".
    private func containsKeyword(_ row: String, _ keywords: [String]) -> Bool {
        let normalized = " " + String(row.lowercased().map { $0.isLetter ? $0 : " " }) + " "
        return keywords.contains { normalized.contains(" \($0.replacingOccurrences(of: "-", with: " ")) ") }
    }

    private func containsWord(_ text: String, _ word: String) -> Bool {
        let normalized = " " + String(text.map { $0.isLetter ? $0 : " " }) + " "
        return normalized.contains(" \(word) ")
    }
}
