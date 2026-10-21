import CoreGraphics
import Foundation
import Testing
@testable import ReceiptKit

private func dec(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

// MARK: - AmountParser

@Suite("AmountParser")
struct AmountParserTests {
    @Test(arguments: [
        ("12.50", "12.50"),
        ("9,99", "9.99"),
        ("1 234,56", "1234.56"),
        ("1,234.56", "1234.56"),
        ("1.234,56", "1234.56"),
        ("-3.00", "-3.00"),
        ("€4,20", "4.20"),
    ])
    func parsesAmount(input: String, expected: String) {
        #expect(AmountParser.matches(in: input).map(\.value) == [dec(expected)])
    }

    @Test(arguments: ["Bread 2", "Qty 12", "Weight 1.500 kg", "Nizami St 12, Baku"])
    func ignoresNonMoneyNumbers(input: String) {
        #expect(AmountParser.matches(in: input).isEmpty)
    }
}

// MARK: - RowGrouper

@Suite("RowGrouper")
struct RowGrouperTests {
    @Test func mergesObservationsOnTheSameRowLeftToRight() {
        let lines = [
            RecognizedLine(text: "3.50", boundingBox: CGRect(x: 0.70, y: 0.805, width: 0.2, height: 0.05)),
            RecognizedLine(text: "Total 3.50", boundingBox: CGRect(x: 0.10, y: 0.50, width: 0.5, height: 0.05)),
            RecognizedLine(text: "Coffee", boundingBox: CGRect(x: 0.10, y: 0.80, width: 0.3, height: 0.05)),
        ]
        #expect(RowGrouper.rows(from: lines, minimumConfidence: 0) == ["Coffee 3.50", "Total 3.50"])
    }

    @Test func dropsLowConfidenceLines() {
        let lines = [
            RecognizedLine(text: "Shop", confidence: 0.9),
            RecognizedLine(text: "#@!", confidence: 0.1),
        ]
        #expect(RowGrouper.rows(from: lines, minimumConfidence: 0.3) == ["Shop"])
    }
}

// MARK: - ReceiptParser

@Suite("ReceiptParser")
struct ReceiptParserTests {
    let parser = ReceiptParser(configuration: .default)

    @Test func parsesTypicalCafeReceipt() throws {
        let receipt = parser.parse(rows: [
            "CAFE NOIR",
            "Nizami St 12, Baku",
            "21.10.2026 11:07",
            "Latte 2 x 3.50 7.00",
            "Croissant 4.20",
            "Subtotal 11.20",
            "VAT 18% 1.71",
            "TOTAL 11.20 AZN",
            "CARD 11.20",
        ])

        #expect(receipt.merchant == "CAFE NOIR")
        #expect(receipt.currencyCode == "AZN")
        #expect(receipt.total == Money(amount: dec("11.20"), currencyCode: "AZN"))
        #expect(receipt.items == [
            ReceiptLineItem(name: "Latte", quantity: 2, total: Money(amount: dec("7.00"), currencyCode: "AZN")),
            ReceiptLineItem(name: "Croissant", total: Money(amount: dec("4.20"), currencyCode: "AZN")),
        ])

        let date = try #require(receipt.date)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 21)
    }

    @Test func readsTotalPrintedOnTheNextRow() {
        let receipt = parser.parse(rows: ["SHOP", "Bread 1.20", "TOTAL", "1.20"])
        #expect(receipt.total?.amount == dec("1.20"))
        #expect(receipt.items.map(\.name) == ["Bread"])
    }

    @Test func subtotalIsNotTheTotal() {
        let receipt = parser.parse(rows: ["SHOP", "Tea 2.00", "Subtotal 2.00", "Tip 0.50", "Total 2.50"])
        #expect(receipt.total?.amount == dec("2.50"))
        #expect(receipt.items.map(\.name) == ["Tea"])
    }

    @Test func detectsCurrencySymbol() {
        #expect(parser.parse(rows: ["Pret", "Wrap £4.20", "Total £4.20"]).currencyCode == "GBP")
    }

    @Test func discountBecomesNegativeItem() {
        let receipt = parser.parse(rows: ["SHOP", "Juice 3.00", "Discount -0.50", "Total 2.50"])
        let sum = receipt.items.reduce(Decimal(0)) { $0 + $1.total.amount }
        #expect(sum == receipt.total?.amount)
    }
}

// MARK: - ReceiptScanner (end to end, OCR stubbed)

private struct StubRecognizer: TextRecognizing {
    let lines: [RecognizedLine]
    func recognizeText(in image: CGImage, configuration: ReceiptKitConfiguration) async throws -> [RecognizedLine] {
        lines
    }
}

private func blankImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

@Suite("ReceiptScanner")
struct ReceiptScannerTests {
    @Test func warnsWhenItemsDoNotAddUp() async throws {
        let scanner = ReceiptScanner(recognizer: StubRecognizer(lines: [
            RecognizedLine(text: "SHOP"),
            RecognizedLine(text: "01.02.2026"),
            RecognizedLine(text: "Tea 2.00"),
            RecognizedLine(text: "Cake 3.00"),
            RecognizedLine(text: "TOTAL 6.00"),
        ]))

        let result = try await scanner.scan(blankImage())

        #expect(result.warnings == [.itemsDoNotSumToTotal(itemsSum: dec("5.00"), total: dec("6.00"))])
        #expect(result.needsReview)
    }

    @Test func cleanReceiptHasNoWarnings() async throws {
        let scanner = ReceiptScanner(recognizer: StubRecognizer(lines: [
            RecognizedLine(text: "SHOP"),
            RecognizedLine(text: "01.02.2026"),
            RecognizedLine(text: "Tea 2.00"),
            RecognizedLine(text: "TOTAL 2.00"),
        ]))
        #expect(try await scanner.scan(blankImage()).warnings.isEmpty)
    }

    @Test func throwsWhenNoTextFound() async {
        let scanner = ReceiptScanner(recognizer: StubRecognizer(lines: []))
        await #expect(throws: ReceiptScanError.noTextFound) {
            try await scanner.scan(blankImage())
        }
    }
}
