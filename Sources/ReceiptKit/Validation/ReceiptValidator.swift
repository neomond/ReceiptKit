import Foundation

/// Cross-checks the extracted receipt. Warnings, not errors: a receipt with a
/// missing date is still useful, it just needs the user to confirm.
enum ReceiptValidator {
    static let lowConfidenceThreshold: Float = 0.5

    static func warnings(
        for receipt: Receipt,
        lines: [RecognizedLine],
        configuration: ReceiptKitConfiguration
    ) -> [ReceiptWarning] {
        var warnings: [ReceiptWarning] = []

        if receipt.merchant == nil { warnings.append(.merchantNotFound) }
        if receipt.date == nil { warnings.append(.dateNotFound) }

        if let total = receipt.total {
            if !receipt.items.isEmpty {
                let itemsSum = receipt.items.reduce(Decimal(0)) { $0 + $1.total.amount }
                if abs(itemsSum - total.amount) > configuration.sumTolerance {
                    warnings.append(.itemsDoNotSumToTotal(itemsSum: itemsSum, total: total.amount))
                }
            }
        } else {
            warnings.append(.totalNotFound)
        }

        if !lines.isEmpty {
            let average = lines.reduce(Float(0)) { $0 + $1.confidence } / Float(lines.count)
            if average < lowConfidenceThreshold {
                warnings.append(.lowRecognitionConfidence(average: Double(average)))
            }
        }

        return warnings
    }
}
