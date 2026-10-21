import Foundation

/// A monetary amount. `Decimal`, never `Double`, so totals add up exactly.
public struct Money: Sendable, Hashable, Codable {
    public var amount: Decimal
    public var currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

public struct ReceiptLineItem: Sendable, Hashable, Codable {
    public var name: String
    public var quantity: Int
    /// Line total (quantity × unit price), as printed on the receipt.
    public var total: Money

    public init(name: String, quantity: Int = 1, total: Money) {
        self.name = name
        self.quantity = max(quantity, 1)
        self.total = total
    }

    public var unitPrice: Money {
        Money(amount: total.amount / Decimal(quantity), currencyCode: total.currencyCode)
    }
}

public struct Receipt: Sendable, Hashable, Codable {
    public var merchant: String?
    public var date: Date?
    public var items: [ReceiptLineItem]
    public var total: Money?
    public var currencyCode: String

    public init(
        merchant: String? = nil,
        date: Date? = nil,
        items: [ReceiptLineItem] = [],
        total: Money? = nil,
        currencyCode: String
    ) {
        self.merchant = merchant
        self.date = date
        self.items = items
        self.total = total
        self.currencyCode = currencyCode
    }
}

/// Non-fatal problems found after extraction. The host app decides what to do
/// with them (e.g. ask the user to confirm the total).
public enum ReceiptWarning: Sendable, Hashable {
    case merchantNotFound
    case dateNotFound
    case totalNotFound
    case itemsDoNotSumToTotal(itemsSum: Decimal, total: Decimal)
    case lowRecognitionConfidence(average: Double)
}

public enum ReceiptScanError: Error, Sendable, Equatable {
    case noTextFound
    case recognitionFailed(String)
}

public struct ReceiptScanResult: Sendable {
    public let receipt: Receipt
    public let warnings: [ReceiptWarning]
    /// Raw OCR output, kept for debugging and for building an evaluation set.
    public let recognizedLines: [RecognizedLine]

    public var needsReview: Bool { !warnings.isEmpty }

    public init(receipt: Receipt, warnings: [ReceiptWarning], recognizedLines: [RecognizedLine]) {
        self.receipt = receipt
        self.warnings = warnings
        self.recognizedLines = recognizedLines
    }
}
