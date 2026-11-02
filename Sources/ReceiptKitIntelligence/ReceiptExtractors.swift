import Foundation
import ReceiptKit

public enum ReceiptIntelligenceError: Error, Sendable, Equatable {
    case modelUnavailable(String)
}

public enum ReceiptExtractors {
    /// The best extractor this device supports:
    /// Foundation Models with heuristic fallback on iOS/macOS 26+ when Apple
    /// Intelligence is available, otherwise the heuristic extractor alone.
    public static func bestAvailable() -> any ReceiptExtracting {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), FoundationModelsReceiptExtractor.isAvailable {
            return FallbackReceiptExtractor(
                primary: FoundationModelsReceiptExtractor(),
                fallback: HeuristicReceiptExtractor()
            )
        }
        #endif
        return HeuristicReceiptExtractor()
    }
}

/// Guards against amounts the model invented: every total and item amount must
/// appear in the OCR text as a money-looking number (with a decimal part).
///
/// Example it catches: "VÖEN: 1600252451" (a tax ID) returned as the total.
/// A number counts as money only with 1–2 decimals ("1.0", "12,50"), which
/// IDs, phone numbers and dates without decimals never have.
enum AmountGrounding {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func printedAmounts(in rows: [String]) -> [Decimal] {
        rows.flatMap { row in
            row.matches(of: #/\d{1,3}(?:[ ,]\d{3})+[.,]\d{1,2}(?!\d)|\d+[.,]\d{1,2}(?!\d)/#)
                .compactMap { parse(String($0.output)) }
        }
    }

    static func parse(_ raw: String) -> Decimal? {
        let compact = raw.replacingOccurrences(of: " ", with: "")
        guard let separator = compact.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
        let integerPart = compact[..<separator].filter { $0.isASCII && $0.isNumber }
        let fractionPart = compact[compact.index(after: separator)...]
        guard !integerPart.isEmpty else { return nil }
        return Decimal(string: "\(integerPart).\(fractionPart)", locale: posix)
    }

    /// Drops the total and any item whose amount is not printed on the receipt.
    /// Missing is better than wrong: a missing total makes the scan ask for
    /// review, while a wrong one would be saved silently.
    static func grounded(_ receipt: Receipt, in rows: [String]) -> Receipt {
        let printed = printedAmounts(in: rows)
        func isPrinted(_ amount: Decimal) -> Bool {
            let magnitude = abs(amount)
            return printed.contains { $0 == magnitude }
        }

        var result = receipt
        if let total = result.total, !isPrinted(total.amount) {
            result.total = nil
        }
        result.items = result.items.filter { isPrinted($0.total.amount) }
        return result
    }
}

struct DraftLineItem: Equatable {
    var name: String
    var quantity: Int
    var total: Double
}

/// Turns the model's loosely-typed output (strings, doubles) into a `Receipt`.
/// Kept free of Foundation Models types so it is unit-testable on any OS.
enum ReceiptAssembler {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func receipt(
        merchant: String,
        date: String,
        currencyCode: String,
        items: [DraftLineItem],
        total: Double,
        defaultCurrency: String
    ) -> Receipt {
        let currency = normalizedCurrency(currencyCode) ?? defaultCurrency

        let lineItems = items.compactMap { item -> ReceiptLineItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let amount = decimal(item.total), amount != 0 else { return nil }
            return ReceiptLineItem(name: name, quantity: item.quantity, total: Money(amount: amount, currencyCode: currency))
        }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)

        return Receipt(
            merchant: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            date: isoDate(date),
            items: lineItems,
            total: decimal(total).flatMap { $0 > 0 ? Money(amount: $0, currencyCode: currency) : nil },
            currencyCode: currency
        )
    }

    /// Rounds to cents through a string, so 11.2 becomes exactly 11.20.
    static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        return Decimal(string: String(format: "%.2f", value), locale: posix)
    }

    static func isoDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }

    static func normalizedCurrency(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch code {
        case "₼", "MAN", "MANAT": return "AZN"
        case "£": return "GBP"
        case "€": return "EUR"
        case "$": return "USD"
        case "₽", "РУБ": return "RUB"
        default:
            return code.count == 3 && code.allSatisfy({ $0.isASCII && $0.isLetter }) ? code : nil
        }
    }
}
