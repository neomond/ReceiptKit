import Foundation
import ReceiptKit

public enum ReportFormatter {
    /// Side-by-side comparison table, ready to paste into the README.
    public static func markdownTable(_ reports: [EvaluationReport]) -> String {
        guard let first = reports.first else { return "_No reports._" }

        var rows: [(String, (EvaluationReport) -> String)] = [
            ("Merchant", { percent($0.accuracy(\.merchant)) }),
            ("Date", { percent($0.accuracy(\.date)) }),
            ("Total", { percent($0.accuracy(\.total)) }),
            ("Currency", { percent($0.accuracy(\.currency)) }),
            ("Items precision", { percent($0.itemPrecision) }),
            ("Items recall", { percent($0.itemRecall) }),
            ("Items F1", { percent($0.itemF1) }),
            ("**Fully correct receipts**", { "**\(percent($0.fullyCorrectRate))**" }),
            ("Items sum to total", { percent($0.selfConsistentRate) }),
            ("Latency p50", { milliseconds($0.latencyPercentile(0.5)) }),
            ("Latency p95", { milliseconds($0.latencyPercentile(0.95)) }),
        ]
        if reports.contains(where: { $0.errorCount > 0 }) {
            rows.append(("Errors", { "\($0.errorCount)" }))
        }

        var lines = [
            "| Metric (n = \(first.receiptCount)) | " + reports.map(\.extractorName).joined(separator: " | ") + " |",
            "|---|" + String(repeating: "---:|", count: reports.count),
        ]
        for (title, value) in rows {
            lines.append("| \(title) | " + reports.map(value).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// Per-receipt breakdown of what went wrong, for debugging an extractor.
    public static func failures(_ report: EvaluationReport, fixtures: [ReceiptFixture]) -> String {
        let expectedByID = Dictionary(fixtures.map { ($0.id, $0.expected) }, uniquingKeysWith: { first, _ in first })
        var output: [String] = []

        for result in report.results {
            guard let expected = expectedByID[result.fixtureID] else { continue }

            if let error = result.error {
                output.append("✗ \(result.fixtureID): error: \(error)")
                continue
            }
            guard let score = result.score, let predicted = result.predicted, !score.isFullyCorrect else { continue }

            var problems: [String] = []
            if !score.merchant {
                problems.append("merchant: expected \(show(expected.merchant)), got \(show(predicted.merchant))")
            }
            if !score.date {
                problems.append("date: expected \(show(expected.date)), got \(show(predicted.date.map(FixtureFormat.dateString)))")
            }
            if !score.total {
                problems.append("total: expected \(show(expected.total)), got \(show(predicted.total.map { FixtureFormat.amountString($0.amount) }))")
            }
            if !score.currency {
                problems.append("currency: expected \(expected.currency), got \(predicted.currencyCode)")
            }
            if !score.itemsExact {
                problems.append("items: matched \(score.matchedItems), predicted \(score.predictedItems), expected \(score.expectedItems)")
                problems.append("  expected: " + expected.items.map { "\($0.name) \($0.total)" }.joined(separator: "; "))
                problems.append("  got:      " + predicted.items.map { "\($0.name) \(FixtureFormat.amountString($0.total.amount))" }.joined(separator: "; "))
            }
            output.append("✗ \(result.fixtureID)\n    " + problems.joined(separator: "\n    "))
        }

        return output.isEmpty ? "All receipts fully correct." : output.joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let ms = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        return ms < 10 ? String(format: "%.2f ms", ms) : String(format: "%.0f ms", ms)
    }

    private static func show(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "nil"
    }
}
