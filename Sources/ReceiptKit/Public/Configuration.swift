import Foundation

public struct ReceiptKitConfiguration: Sendable {
    /// Used when no currency symbol or code is found on the receipt.
    public var defaultCurrencyCode: String
    /// BCP-47 identifiers passed to Vision text recognition.
    public var recognitionLanguages: [String]
    /// OCR lines below this confidence are ignored by the heuristic extractor.
    public var minimumLineConfidence: Float
    /// Allowed difference between the sum of line items and the printed total.
    public var sumTolerance: Decimal
    /// Lower-cased words that mark the grand-total row.
    public var totalKeywords: [String]
    /// Lower-cased words that mark rows which are never line items
    /// (subtotal, tax, payment method, change...).
    public var nonItemKeywords: [String]

    public init(
        defaultCurrencyCode: String = "AZN",
        recognitionLanguages: [String] = ["en-US", "ru-RU"],
        minimumLineConfidence: Float = 0.3,
        sumTolerance: Decimal = Decimal(string: "0.01", locale: Locale(identifier: "en_US_POSIX"))!,
        totalKeywords: [String] = ["total", "grand total", "amount due", "balance due", "to pay",
                                   "итого", "к оплате", "cəmi", "yekun"],
        nonItemKeywords: [String] = ["subtotal", "sub total", "sub-total", "tax", "vat", "ədv", "ндс",
                                     "cash", "card", "change", "visa", "mastercard", "tip", "сдача"]
    ) {
        self.defaultCurrencyCode = defaultCurrencyCode
        self.recognitionLanguages = recognitionLanguages
        self.minimumLineConfidence = minimumLineConfidence
        self.sumTolerance = sumTolerance
        self.totalKeywords = totalKeywords
        self.nonItemKeywords = nonItemKeywords
    }

    public static let `default` = ReceiptKitConfiguration()
}
