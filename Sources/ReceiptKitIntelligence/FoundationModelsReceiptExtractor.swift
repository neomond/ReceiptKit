#if canImport(FoundationModels)
import Foundation
import FoundationModels
import ReceiptKit

/// Extracts a receipt from OCR text with Apple's on-device language model,
/// using guided generation (`@Generable`) so the output is always a typed
/// struct, never free text that needs parsing.
///
/// Throws when the model is unavailable or the receipt exceeds the context
/// window; wrap it in `FallbackReceiptExtractor` (or use
/// `ReceiptExtractors.bestAvailable()`) to fall back to heuristics.
@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsReceiptExtractor: ReceiptExtracting {
    /// When true (default), any total or item amount the model returns that is
    /// not printed on the receipt as a money amount is discarded. Catches the
    /// model turning a tax ID or phone number into a price.
    public var groundsAmounts: Bool

    public init(groundsAmounts: Bool = true) {
        self.groundsAmounts = groundsAmounts
    }

    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Why the model can't be used (Apple Intelligence off, device not
    /// eligible, model still downloading), or `nil` when it can.
    public static var unavailabilityReason: String? {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability {
            return String(describing: reason)
        }
        return nil
    }

    public func extract(from lines: [RecognizedLine], configuration: ReceiptKitConfiguration) async throws -> Receipt {
        if let reason = Self.unavailabilityReason {
            throw ReceiptIntelligenceError.modelUnavailable(reason)
        }

        let rows = ReceiptLayout.rows(from: lines, minimumConfidence: configuration.minimumLineConfidence)

        // A fresh session per receipt: no transcript carried between receipts.
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Receipt text:\n" + rows.joined(separator: "\n"),
            generating: GeneratedReceipt.self,
            // Greedy decoding: same input, same output. Required for a fair evaluation.
            options: GenerationOptions(samplingMode: .greedy)
        )

        let generated = response.content
        let receipt = ReceiptAssembler.receipt(
            merchant: generated.merchant,
            date: generated.date,
            currencyCode: generated.currencyCode,
            items: generated.items.map { DraftLineItem(name: $0.name, quantity: $0.quantity, total: $0.total) },
            total: generated.total,
            defaultCurrency: configuration.defaultCurrencyCode
        )
        return groundsAmounts ? AmountGrounding.grounded(receipt, in: rows) : receipt
    }

    static let instructions = """
        You extract structured data from the OCR text of a shop receipt.
        The text can be in English, Azerbaijani or Russian and can contain OCR errors.

        Rules:
        - merchant: the shop's trading name as a customer would say it, without legal form \
        (MMC, LLC, ООО) and without tax or fiscal IDs (VÖEN, ИНН).
        - items: only purchased products, in printed order. Never include subtotal, tax \
        (VAT, ƏDV, НДС), payment method, cash given, change, bonus or loyalty points, cashier, \
        fiscal or tax ID lines.
        - For each item, total is the line total. If a quantity and unit price are printed, \
        quantity is the count and total is quantity times unit price as printed.
        - A discount is its own item with a negative total.
        - total: the final amount paid.
        - Copy numbers exactly as printed. Never invent values.
        - If a field is not on the receipt, use an empty string, or 0 for numbers.
        """
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedReceipt {
    @Guide(description: "Shop trading name, or empty string if not printed")
    var merchant: String

    @Guide(description: "Purchase date as yyyy-MM-dd, or empty string if not printed")
    var date: String

    @Guide(description: "ISO 4217 currency code such as AZN, GBP, EUR, USD or RUB")
    var currencyCode: String

    @Guide(description: "Purchased products in printed order; discounts have a negative total")
    var items: [GeneratedLineItem]

    @Guide(description: "Final amount paid, or 0 if not printed")
    var total: Double
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedLineItem {
    @Guide(description: "Product name as printed")
    var name: String

    @Guide(description: "Number of units; 1 if not printed or sold by weight")
    var quantity: Int

    @Guide(description: "Line total for this product")
    var total: Double
}
#endif
