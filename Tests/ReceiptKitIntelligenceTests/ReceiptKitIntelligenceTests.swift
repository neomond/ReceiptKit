import Foundation
import Testing
import ReceiptKit
@testable import ReceiptKitIntelligence

private func dec(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

@Suite("ReceiptAssembler")
struct ReceiptAssemblerTests {
    @Test func convertsModelOutputToReceipt() throws {
        let receipt = ReceiptAssembler.receipt(
            merchant: "  Cafe Noir ",
            date: "2026-10-21",
            currencyCode: "azn",
            items: [
                DraftLineItem(name: "Latte", quantity: 2, total: 7.0),
                DraftLineItem(name: "Croissant", quantity: 1, total: 4.2),
                DraftLineItem(name: "Discount", quantity: 1, total: -0.5),
            ],
            total: 10.7,
            defaultCurrency: "GBP"
        )

        #expect(receipt.merchant == "Cafe Noir")
        #expect(receipt.currencyCode == "AZN")
        #expect(receipt.total == Money(amount: dec("10.70"), currencyCode: "AZN"))
        #expect(receipt.items.map(\.total.amount) == [dec("7.00"), dec("4.20"), dec("-0.50")])
        #expect(receipt.items[0].quantity == 2)

        let date = try #require(receipt.date)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 21)
    }

    @Test func emptyAndZeroMeanMissing() {
        let receipt = ReceiptAssembler.receipt(
            merchant: "", date: "", currencyCode: "", items: [DraftLineItem(name: " ", quantity: 1, total: 3)],
            total: 0, defaultCurrency: "AZN"
        )
        #expect(receipt.merchant == nil)
        #expect(receipt.date == nil)
        #expect(receipt.total == nil)
        #expect(receipt.items.isEmpty)
        #expect(receipt.currencyCode == "AZN")
    }

    @Test(arguments: [("₼", "AZN"), ("manat", "AZN"), ("£", "GBP"), ("eur", "EUR")])
    func normalizesCurrency(raw: String, expected: String) {
        #expect(ReceiptAssembler.normalizedCurrency(raw) == expected)
    }

    @Test(arguments: ["dollars", "", "12"])
    func rejectsUnknownCurrency(raw: String) {
        #expect(ReceiptAssembler.normalizedCurrency(raw) == nil)
    }

    @Test func doubleRoundsToExactCents() {
        // 0.1 + 0.2 is 0.30000000000000004 as a Double.
        #expect(ReceiptAssembler.decimal(0.1 + 0.2) == dec("0.30"))
        #expect(ReceiptAssembler.decimal(.nan) == nil)
    }

    @Test func rejectsInvalidDate() {
        #expect(ReceiptAssembler.isoDate("2026-13-40") == nil)
        #expect(ReceiptAssembler.isoDate("21.10.2026") == nil)
    }
}

// MARK: - Grounding

@Suite("AmountGrounding")
struct AmountGroundingTests {
    // Real case from the first labeled receipt: the model returned the VÖEN as the total.
    let rows = [
        "Bakılift-2",
        "VÖEN: 1600252451",
        "Ödəniş növü: Lift xidmət haqqı",
        "NAĞD ÖDƏNİŞ: 1.0 AZN",
        "Tarix: 04.10.2026 16:20:11",
    ]

    @Test func findsMoneyLookingNumbersOnly() {
        let printed = AmountGrounding.printedAmounts(in: rows)
        #expect(printed.contains(dec("1.00")))
        #expect(!printed.contains(dec("1600252451")))
    }

    @Test func dropsInventedTotalAndItems() {
        let hallucinated = Receipt(
            merchant: "Bakilift-2",
            items: [ReceiptLineItem(name: "Lift xidmat haqqi", total: Money(amount: dec("1600252451"), currencyCode: "AZN"))],
            total: Money(amount: dec("1600252451"), currencyCode: "AZN"),
            currencyCode: "AZN"
        )
        let grounded = AmountGrounding.grounded(hallucinated, in: rows)
        #expect(grounded.total == nil)
        #expect(grounded.items.isEmpty)
        #expect(grounded.merchant == "Bakilift-2")
    }

    @Test func keepsPrintedAmountsIncludingDiscounts() {
        let receipt = Receipt(
            items: [
                ReceiptLineItem(name: "Juice", total: Money(amount: dec("3.00"), currencyCode: "AZN")),
                ReceiptLineItem(name: "Discount", total: Money(amount: dec("-0.50"), currencyCode: "AZN")),
            ],
            total: Money(amount: dec("2.50"), currencyCode: "AZN"),
            currencyCode: "AZN"
        )
        let grounded = AmountGrounding.grounded(receipt, in: ["Juice 3.00", "Endirim -0,50", "Cəmi 2,50"])
        #expect(grounded == receipt)
    }
}

// MARK: - Fallback

private struct FailingExtractor: ReceiptExtracting {
    func extract(from lines: [RecognizedLine], configuration: ReceiptKitConfiguration) async throws -> Receipt {
        throw ReceiptIntelligenceError.modelUnavailable("test")
    }
}

@Suite("FallbackReceiptExtractor")
struct FallbackReceiptExtractorTests {
    @Test func usesFallbackWhenPrimaryThrows() async throws {
        let extractor = FallbackReceiptExtractor(primary: FailingExtractor(), fallback: HeuristicReceiptExtractor())
        let receipt = try await extractor.extract(
            from: ["SHOP", "Tea 2.00", "TOTAL 2.00"].map { RecognizedLine(text: $0) },
            configuration: .default
        )
        #expect(receipt.total?.amount == dec("2.00"))
    }

    @Test func bestAvailableNeverThrowsForReadableText() async throws {
        // Heuristic-only on machines without Apple Intelligence; LLM + fallback otherwise.
        // Only checks that it returns; output quality is measured by receiptkit-eval, not unit tests.
        let receipt = try await ReceiptExtractors.bestAvailable().extract(
            from: ["SHOP", "Tea 2.00", "TOTAL 2.00"].map { RecognizedLine(text: $0) },
            configuration: .default
        )
        #expect(!receipt.currencyCode.isEmpty)
    }
}
