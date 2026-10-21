# ReceiptKit

On-device receipt scanning SDK for iOS: **image → OCR → structured receipt → validation**.
No network, no backend; receipts never leave the phone.

- **Swift 6** strict concurrency, `Sendable` throughout
- Swift-native **Vision** OCR (`RecognizeTextRequest`, iOS 18+)
- Pluggable pipeline: swap the OCR engine or the extractor (e.g. an on-device LLM) via protocols
- Optional **UIKit** capture screen (`ReceiptKitUI`) built on the system document camera
- Unit tested with **Swift Testing**

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/neomond/ReceiptKit", from: "0.1.0")
```

Add `ReceiptKit` (core) and, if you want the ready-made screen, `ReceiptKitUI`.

## Usage

### Core API

```swift
import ReceiptKit

let scanner = ReceiptScanner()
let result = try await scanner.scan(cgImage)

result.receipt.merchant      // "CAFE NOIR"
result.receipt.total         // Money(amount: 11.20, currencyCode: "AZN")
result.receipt.items         // [Latte ×2 7.00, Croissant 4.20]
result.warnings              // [] or e.g. [.itemsDoNotSumToTotal(itemsSum: 5.00, total: 6.00)]
result.needsReview           // true if anything should be confirmed by the user
```

### UIKit host

```swift
import ReceiptKitUI

final class ExpensesViewController: UIViewController, ReceiptCaptureViewControllerDelegate {
    @objc private func scanTapped() {
        let capture = ReceiptCaptureViewController()
        capture.delegate = self
        present(capture, animated: true)
    }

    func receiptCapture(_ controller: ReceiptCaptureViewController, didFinishWith result: ReceiptScanResult) {
        controller.dismiss(animated: true)
        // save result.receipt, or show a review screen if result.needsReview
    }

    func receiptCapture(_ controller: ReceiptCaptureViewController, didFailWith error: any Error) {
        controller.dismiss(animated: true)
    }

    func receiptCaptureDidCancel(_ controller: ReceiptCaptureViewController) {
        controller.dismiss(animated: true)
    }
}
```

Add `NSCameraUsageDescription` to the host app's Info.plist.

### Customizing

```swift
let scanner = ReceiptScanner(
    configuration: ReceiptKitConfiguration(defaultCurrencyCode: "GBP"),
    recognizer: MyOCREngine(),              // any TextRecognizing
    extractor: FoundationModelsExtractor()  // any ReceiptExtracting
)
```

## Architecture

```
ReceiptScanner (public facade)
  │
  ├─ TextRecognizing ──────── VisionTextRecognizer      image → [RecognizedLine]
  │
  ├─ ReceiptExtracting ────── HeuristicReceiptExtractor [RecognizedLine] → Receipt
  │                              ├─ RowGrouper           merge OCR fragments into printed rows
  │                              ├─ AmountParser         money amounts, locale-agnostic separators
  │                              ├─ DateParser           day-first + ISO dates
  │                              └─ ReceiptParser        merchant / items / total / currency
  │
  └─ ReceiptValidator ─────── [ReceiptWarning]          items vs total, missing fields, OCR confidence
```

Design decisions:

| Decision | Why |
|---|---|
| `Decimal` for money | `Double` can't represent 0.10 exactly; totals must add up to the cent |
| Warnings instead of throwing | A receipt with no date is still useful; the host decides how to handle it |
| Protocols at both pipeline steps | Testable without a camera; lets an LLM extractor replace heuristics with a fallback |
| Language correction off | Vision's correction turns prices and codes into dictionary words |
| Only 2-decimal numbers count as money | Filters out quantities, weights (1.500 kg) and street numbers |
| Core and UI as separate products | Hosts with their own camera flow don't pull in UIKit code |

## Known limitations

- Single page only (first page of the document scan).
- Day-first dates; US `MM/dd` receipts will be misread.
- Heuristic extraction struggles with multi-column layouts and items spanning two lines. This is what the Foundation Models extractor (roadmap) is for.

## Roadmap

- [ ] `FoundationModelsExtractor`: `@Generable` receipt schema, falls back to heuristics when the model is unavailable
- [ ] Evaluation set (~100 labeled receipts) + script reporting field accuracy per extractor
- [ ] XCFramework distribution (wrapper framework target, `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`)
- [ ] Multi-page receipts

---

## Part of: InsightFinance (host app)

ReceiptKit is the first module of a larger personal-finance app:

```
InsightFinance/
├── App/                     SwiftUI app shell, dependency container, navigation
├── Packages/
│   ├── ReceiptKit/          ← this package (SDK, UIKit capture)
│   ├── Domain/              Transaction, Category, Budget; repository protocols; no frameworks
│   ├── Data/                SwiftData persistence; TransactionStore actor; FX rates (REST + WebSocket)
│   ├── Categorizer/         Core ML expense classifier (trained in Python, converted + quantized)
│   ├── Assistant/           Foundation Models chat with tool calling; read-only tools,
│   │                        writes go through a user confirmation step
│   └── Features/
│       ├── Dashboard/       Swift Charts, @Observable view models
│       ├── Transactions/    list, detail, edit
│       └── Scan/            ReceiptKit → review screen → save
└── Tools/ml/                training + coremltools conversion + evaluation scripts
```

Build order: ReceiptKit → Domain/Data → Dashboard → Categorizer → Assistant.
