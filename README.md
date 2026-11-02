# ReceiptKit

On-device receipt scanning SDK for iOS: **image → OCR → structured receipt → validation**.
No network, no backend; receipts never leave the phone.

- **Swift 6** strict concurrency, `Sendable` throughout
- Swift-native **Vision** OCR (`RecognizeTextRequest`, iOS 18+)
- Pluggable pipeline: swap the OCR engine or the extractor (e.g. an on-device LLM) via protocols
- Optional **UIKit** capture screen (`ReceiptKitUI`) built on the system document camera
- Optional **on-device LLM extraction** (`ReceiptKitIntelligence`): Apple Foundation Models with guided generation, falling back to heuristics
- **Measured, not claimed**: an evaluation harness compares extractors on labeled real receipts ([results](#evaluation))
- Unit tested with **Swift Testing**

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/neomond/ReceiptKit", from: "0.1.0")
```

| Product | Use it for | Minimum OS |
|---|---|---|
| `ReceiptKit` | Core: OCR, heuristic extraction, validation | iOS 18 |
| `ReceiptKitUI` | Ready-made UIKit capture screen | iOS 18 |
| `ReceiptKitIntelligence` | On-device LLM extractor with fallback | iOS 18 (LLM used on iOS 26+) |
| `ReceiptKitEvaluation` | Fixture format and scoring, for building your own eval set | iOS 18 / macOS 15 |

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

### Example app

`Example/ReceiptKitDemo` is a minimal UIKit app: scan a receipt, see the parsed result next to the raw OCR, and export the scan as an evaluation fixture. Open `Example/ReceiptKitDemo/ReceiptKitDemo.xcodeproj` and run it on an iPhone (the simulator has no document camera).

### Customizing

```swift
let scanner = ReceiptScanner(
    configuration: ReceiptKitConfiguration(defaultCurrencyCode: "GBP"),
    recognizer: MyOCREngine(),   // any TextRecognizing
    extractor: MyExtractor()     // any ReceiptExtracting
)
```

### On-device LLM extraction

```swift
import ReceiptKitIntelligence

// Foundation Models + heuristic fallback where Apple Intelligence is available,
// heuristic alone everywhere else. No availability checks needed in the host.
let scanner = ReceiptScanner(extractor: ReceiptExtractors.bestAvailable())
```

The LLM never sees the image. It gets the OCR text in reading order and fills a typed `@Generable` struct, so its output can't be malformed, and decoding is greedy so the same receipt always gives the same answer. Anything that goes wrong (model unavailable, receipt too long for the context window) falls back to the heuristic extractor.

**Amount grounding.** Every total and item amount the model returns must appear on the receipt as a money-looking number (with decimals), or it is discarded. On the very first labeled receipt, the model returned the shop's tax ID (`VÖEN: 1600252451`) as the total, and its items still summed to that total, so the consistency check alone could not catch it. A missing total makes the scan ask the user to review it; a wrong one would be saved silently.

## Architecture

```
ReceiptScanner (public facade)
  │
  ├─ TextRecognizing ──────── VisionTextRecognizer      image → [RecognizedLine]
  │
  ├─ ReceiptExtracting ────── FallbackReceiptExtractor
  │                              ├─ FoundationModelsReceiptExtractor  on-device LLM (ReceiptKitIntelligence, iOS 26+)
  │                              └─ HeuristicReceiptExtractor         rule-based fallback
  │                                    ├─ RowGrouper      merge OCR fragments into printed rows
  │                                    ├─ AmountParser    money amounts, locale-agnostic separators
  │                                    ├─ DateParser      day-first + ISO dates
  │                                    └─ ReceiptParser   merchant / items / total / currency
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
- Heuristic extraction struggles with multi-column layouts and items spanning two lines. The Foundation Models extractor targets these; the evaluation measures whether it actually helps.
- The on-device model has a limited context window; very long receipts fall back to heuristics.

## Evaluation

Extractors are compared on labeled real receipts (OCR output + hand-checked answer), field by field:

```bash
swift run receiptkit-eval Eval/fixtures --verbose
```

**Results: pending.** The labeled dataset is being collected. See [Eval/README.md](Eval/README.md) for the fixture format, labeling rules and metrics.

## Roadmap

- [x] `FoundationModelsReceiptExtractor`: `@Generable` receipt schema, heuristic fallback
- [x] Evaluation harness: fixture format, scoring, CLI, export from the example app
- [ ] Labeled dataset (50+ real receipts) and published results
- [ ] Hybrid extractor: choose between heuristic and LLM output using the items-sum-to-total check
- [ ] XCFramework distribution (wrapper framework target, `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`)
- [ ] Multi-page receipts

---

## Planned: InsightFinance (host app)

ReceiptKit is the first module of a personal-finance app that is not built yet. Planned structure:

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
