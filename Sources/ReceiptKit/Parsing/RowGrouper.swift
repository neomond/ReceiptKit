import CoreGraphics
import Foundation

/// Vision often returns an item name and its price as two separate observations
/// ("Latte" on the left, "3.50" on the right). This merges observations that sit
/// on the same printed row, then orders rows top to bottom.
enum RowGrouper {
    static func rows(from lines: [RecognizedLine], minimumConfidence: Float) -> [String] {
        let kept = lines.filter {
            $0.confidence >= minimumConfidence && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
        }

        // No geometry (e.g. text from another source): keep the given order.
        if kept.allSatisfy({ $0.boundingBox.isEmpty }) {
            return kept.map { $0.text.trimmingCharacters(in: .whitespaces) }
        }

        // Vision's origin is bottom-left, so a larger midY is higher on the page.
        let sorted = kept.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let anchor = rows.last?.first, sameRow(anchor, line) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }

        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
    }

    private static func sameRow(_ a: RecognizedLine, _ b: RecognizedLine) -> Bool {
        let tolerance = min(a.boundingBox.height, b.boundingBox.height) * 0.5
        return tolerance > 0 && abs(a.boundingBox.midY - b.boundingBox.midY) <= tolerance
    }
}
