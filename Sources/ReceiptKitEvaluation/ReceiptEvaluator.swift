import Foundation
import ReceiptKit

/// The outcome for one fixture.
public struct ReceiptEvaluation: Sendable {
    public var fixtureID: String
    public var expectedItemCount: Int
    public var predicted: Receipt?
    public var score: ReceiptScore?
    /// Set when the extractor threw. Counted as wrong on every field.
    public var error: String?
    public var latency: Duration

    public init(fixtureID: String, expectedItemCount: Int, predicted: Receipt?, score: ReceiptScore?, error: String?, latency: Duration) {
        self.fixtureID = fixtureID
        self.expectedItemCount = expectedItemCount
        self.predicted = predicted
        self.score = score
        self.error = error
        self.latency = latency
    }
}

/// Aggregate metrics for one extractor over the whole fixture set.
public struct EvaluationReport: Sendable {
    public var extractorName: String
    public var results: [ReceiptEvaluation]

    public init(extractorName: String, results: [ReceiptEvaluation]) {
        self.extractorName = extractorName
        self.results = results
    }

    public var receiptCount: Int { results.count }
    public var errorCount: Int { results.filter { $0.error != nil }.count }

    /// Share of all receipts where the field is correct. Errors count as wrong.
    public func accuracy(_ field: KeyPath<ReceiptScore, Bool>) -> Double {
        guard receiptCount > 0 else { return 0 }
        return Double(results.filter { $0.score?[keyPath: field] == true }.count) / Double(receiptCount)
    }

    public var fullyCorrectRate: Double { accuracy(\.isFullyCorrect) }

    // Item metrics are micro-averaged: every line item across all receipts counts once.

    public var itemPrecision: Double {
        let predicted = results.compactMap(\.score).reduce(0) { $0 + $1.predictedItems }
        return predicted == 0 ? 0 : Double(matchedItems) / Double(predicted)
    }

    public var itemRecall: Double {
        let expected = results.reduce(0) { $0 + $1.expectedItemCount }
        return expected == 0 ? 0 : Double(matchedItems) / Double(expected)
    }

    public var itemF1: Double {
        let p = itemPrecision, r = itemRecall
        return p + r == 0 ? 0 : 2 * p * r / (p + r)
    }

    private var matchedItems: Int {
        results.compactMap(\.score).reduce(0) { $0 + $1.matchedItems }
    }

    /// Share of receipts whose predicted items add up to the predicted total.
    /// This is the self-check the SDK runs at scan time (`itemsDoNotSumToTotal`).
    public var selfConsistentRate: Double {
        guard receiptCount > 0 else { return 0 }
        let consistent = results.filter { result in
            guard let receipt = result.predicted, let total = receipt.total, !receipt.items.isEmpty else { return false }
            let sum = receipt.items.reduce(Decimal(0)) { $0 + $1.total.amount }
            return abs(sum - total.amount) <= Decimal(string: "0.01")!
        }
        return Double(consistent.count) / Double(receiptCount)
    }

    public func latencyPercentile(_ percentile: Double) -> Duration {
        let sorted = results.map(\.latency).sorted()
        guard !sorted.isEmpty else { return .zero }
        let index = Int((percentile * Double(sorted.count - 1)).rounded())
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}

public enum ReceiptEvaluator {
    /// Runs `extractor` on every fixture, sequentially so latencies don't interfere.
    ///
    /// With `warmUp`, one untimed run happens first, so a one-off cost (loading
    /// an on-device model) isn't charged to the first receipt.
    public static func evaluate(
        _ extractor: any ReceiptExtracting,
        named name: String,
        on fixtures: [ReceiptFixture],
        configuration: ReceiptKitConfiguration = .default,
        warmUp: Bool = false
    ) async -> EvaluationReport {
        let clock = ContinuousClock()
        var results: [ReceiptEvaluation] = []

        if warmUp, let first = fixtures.first {
            _ = try? await extractor.extract(from: first.recognizedLines, configuration: configuration)
        }

        for fixture in fixtures {
            let lines = fixture.recognizedLines
            let start = clock.now
            do {
                let receipt = try await extractor.extract(from: lines, configuration: configuration)
                results.append(ReceiptEvaluation(
                    fixtureID: fixture.id,
                    expectedItemCount: fixture.expected.items.count,
                    predicted: receipt,
                    score: ReceiptScorer.score(receipt, against: fixture.expected),
                    error: nil,
                    latency: clock.now - start
                ))
            } catch {
                results.append(ReceiptEvaluation(
                    fixtureID: fixture.id,
                    expectedItemCount: fixture.expected.items.count,
                    predicted: nil,
                    score: nil,
                    error: String(describing: error),
                    latency: clock.now - start
                ))
            }
        }

        return EvaluationReport(extractorName: name, results: results)
    }
}
