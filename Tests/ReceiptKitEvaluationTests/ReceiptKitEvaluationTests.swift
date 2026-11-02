import CoreGraphics
import Foundation
import Testing
import ReceiptKit
@testable import ReceiptKitEvaluation

private func dec(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func azn(_ amount: String) -> Money {
    Money(amount: dec(amount), currencyCode: "AZN")
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
}

private let cafeLabel = ExpectedReceipt(
    merchant: "Cafe Noir",
    date: "2026-10-21",
    currency: "AZN",
    total: "11.20",
    items: [
        ExpectedItem(name: "Latte", quantity: 2, total: "7.00"),
        ExpectedItem(name: "Croissant", total: "4.20"),
    ]
)

private let cafePrediction = Receipt(
    merchant: "CAFE NOIR",
    date: date(2026, 10, 21),
    items: [
        ReceiptLineItem(name: "Latte", quantity: 2, total: azn("7.00")),
        ReceiptLineItem(name: "Croissant", total: azn("4.20")),
    ],
    total: azn("11.20"),
    currencyCode: "AZN"
)

// MARK: - Fixture format

@Suite("ReceiptFixture")
struct ReceiptFixtureTests {
    @Test func decodesHandWrittenJSON() throws {
        let json = """
            {
              "expected": {
                "currency": "AZN",
                "date": "2026-10-21",
                "items": [{ "name": "Tea", "total": "2.00" }],
                "merchant": "Shop",
                "total": "2.00"
              },
              "id": "shop-01",
              "lines": [
                { "text": "Shop", "confidence": 0.98, "box": [0.1, 0.9, 0.3, 0.04] },
                { "text": "Tea 2.00", "confidence": 0.95 }
              ]
            }
            """
        let fixture = try JSONDecoder().decode(ReceiptFixture.self, from: Data(json.utf8))

        #expect(fixture.id == "shop-01")
        #expect(fixture.notes == nil)
        #expect(fixture.expected.items == [ExpectedItem(name: "Tea", total: "2.00")])
        #expect(fixture.recognizedLines[0].boundingBox == CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.04))
        #expect(fixture.recognizedLines[1].boundingBox == .zero)
    }

    @Test(arguments: [("7", "7.00"), ("4.2", "4.20"), ("11.20", "11.20"), ("-0.5", "-0.50"), ("1234.567", "1234.57")])
    func formatsAmountsToCents(input: String, expected: String) {
        #expect(FixtureFormat.amountString(dec(input)) == expected)
    }

    @Test func draftLabelsScoreAsFullyCorrectAgainstTheirOwnPrediction() throws {
        let result = ReceiptScanResult(
            receipt: cafePrediction,
            warnings: [],
            recognizedLines: [RecognizedLine(text: "CAFE NOIR", confidence: 0.97, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.4, height: 0.03))]
        )
        let fixture = ReceiptFixture(draftFrom: result, id: "draft")

        // Round trip through JSON, as the demo app → Mac workflow does.
        let data = try FixtureFormat.encoder().encode(fixture)
        let decoded = try JSONDecoder().decode(ReceiptFixture.self, from: data)

        #expect(decoded.notes?.hasPrefix("DRAFT") == true)
        #expect(ReceiptScorer.score(cafePrediction, against: decoded.expected).isFullyCorrect)
    }
}

// MARK: - Scoring

@Suite("ReceiptScorer")
struct ReceiptScorerTests {
    @Test func correctPredictionIsFullyCorrect() {
        let score = ReceiptScorer.score(cafePrediction, against: cafeLabel)
        #expect(score.isFullyCorrect)
        #expect(score.matchedItems == 2)
    }

    @Test(arguments: [
        ("BRAVO SUPERMARKET", "Bravo", true),
        ("Bravo", "Bravo Supermarket MMC", true),
        ("Araz", "Bravo", false),
        ("Ab", "Abc Store", false),  // too short to count as containment
        ("Bakilift-2", "Bakılift-2", true),  // dotless ı written as i
        ("Gülər Market", "GULER MARKET", true),
    ])
    func merchantMatching(predicted: String, expected: String, matches: Bool) {
        #expect(ReceiptScorer.merchantMatches(predicted, expected) == matches)
    }

    @Test func hallucinatedFieldIsWrong() {
        #expect(!ReceiptScorer.merchantMatches("Invented Shop", nil))
        #expect(!ReceiptScorer.dateMatches(date(2026, 1, 1), nil))
        #expect(ReceiptScorer.dateMatches(nil, nil))
    }

    @Test func itemMatchingToleratesOCRTyposButNotWrongAmounts() {
        let expected = [ExpectedItem(name: "Croissant", total: "4.20")]

        let typo = [ReceiptLineItem(name: "Cr0issant", total: azn("4.20"))]
        #expect(ReceiptScorer.matchedItemCount(predicted: typo, expected: expected) == 1)

        let wrongAmount = [ReceiptLineItem(name: "Croissant", total: azn("4.00"))]
        #expect(ReceiptScorer.matchedItemCount(predicted: wrongAmount, expected: expected) == 0)

        let differentProduct = [ReceiptLineItem(name: "Baguette", total: azn("4.20"))]
        #expect(ReceiptScorer.matchedItemCount(predicted: differentProduct, expected: expected) == 0)
    }

    @Test func eachPredictedItemMatchesAtMostOnce() {
        let expected = [ExpectedItem(name: "Water", total: "1.00"), ExpectedItem(name: "Water", total: "1.00")]
        let predicted = [ReceiptLineItem(name: "Water", total: azn("1.00"))]
        #expect(ReceiptScorer.matchedItemCount(predicted: predicted, expected: expected) == 1)
    }
}

// MARK: - Aggregation

@Suite("EvaluationReport")
struct EvaluationReportTests {
    @Test func errorsCountAsWrongAndMetricsAreMicroAveraged() {
        let perfect = ReceiptEvaluation(
            fixtureID: "a", expectedItemCount: 2, predicted: cafePrediction,
            score: ReceiptScorer.score(cafePrediction, against: cafeLabel), error: nil, latency: .milliseconds(10)
        )
        let failed = ReceiptEvaluation(
            fixtureID: "b", expectedItemCount: 2, predicted: nil,
            score: nil, error: "exceededContextWindowSize", latency: .milliseconds(30)
        )
        let report = EvaluationReport(extractorName: "test", results: [perfect, failed])

        #expect(report.accuracy(\.total) == 0.5)
        #expect(report.fullyCorrectRate == 0.5)
        #expect(report.errorCount == 1)
        #expect(report.itemPrecision == 1.0)   // 2 matched / 2 predicted
        #expect(report.itemRecall == 0.5)      // 2 matched / 4 expected
        #expect(abs(report.itemF1 - 2.0 / 3.0) < 1e-9)
        #expect(report.selfConsistentRate == 0.5)
        #expect(report.latencyPercentile(0) == .milliseconds(10))
        #expect(report.latencyPercentile(1) == .milliseconds(30))
    }

    @Test func markdownTableHasAColumnPerExtractor() {
        let a = EvaluationReport(extractorName: "heuristic", results: [])
        let b = EvaluationReport(extractorName: "foundation-models", results: [])
        let table = ReportFormatter.markdownTable([a, b])
        #expect(table.contains("| heuristic | foundation-models |"))
        #expect(table.contains("Fully correct receipts"))
    }
}

// MARK: - End to end

@Suite("ReceiptEvaluator")
struct ReceiptEvaluatorTests {
    @Test func heuristicExtractorOnALabeledFixture() async {
        let fixture = ReceiptFixture(
            id: "cafe",
            lines: ["CAFE NOIR", "21.10.2026 11:07", "Latte 2 x 3.50 7.00", "Croissant 4.20", "TOTAL 11.20 AZN"]
                .map { FixtureLine(text: $0) },
            expected: cafeLabel
        )

        let report = await ReceiptEvaluator.evaluate(HeuristicReceiptExtractor(), named: "heuristic", on: [fixture])

        #expect(report.fullyCorrectRate == 1)
        #expect(ReportFormatter.failures(report, fixtures: [fixture]) == "All receipts fully correct.")
    }
}
