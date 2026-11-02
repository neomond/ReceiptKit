# Evaluation

Measures how well each extractor turns OCR text into a correct receipt, on real labeled receipts.

```bash
swift run receiptkit-eval Eval/fixtures --verbose
swift run receiptkit-eval Eval/fixtures --output Eval/RESULTS.md
```

Extractors compared:

| Name | What it is |
|---|---|
| `heuristic` | Rule-based `HeuristicReceiptExtractor` (baseline) |
| `foundation-models` | Apple's on-device LLM with guided generation (`FoundationModelsReceiptExtractor`), macOS/iOS 26+ with Apple Intelligence on. Amounts not printed on the receipt are discarded (grounding). |
| `foundation-models-ungrounded` | Same model without the grounding step, to measure what grounding buys. Not run by default: pass `--extractor heuristic,foundation-models,foundation-models-ungrounded`. |

Latency excludes OCR and is measured after one untimed warm-up run, so model loading isn't charged to the first receipt.

Both extractors receive the same stored OCR output, so differences come from extraction alone.

## Adding a receipt

1. Scan it with the example app, then tap **Export for evaluation**. AirDrop the `.json` to your Mac.
2. Put the file in `Eval/fixtures/`.
3. Open it. The `expected` block is at the top, pre-filled from the scanner's own guess. **Correct it against the paper receipt** using the rules below.
4. Delete the `"notes": "DRAFT: …"` line. The CLI warns about fixtures still marked DRAFT, because an unchecked label only measures how much the scanner agrees with itself.
5. Before committing, check `lines` for anything private (card numbers, your name on a loyalty receipt) and remove those lines.

## Labeling rules

The labels define what "correct" means, so apply them the same way every time.

| Field | Rule |
|---|---|
| `merchant` | Trading name a customer would use: `"Bravo"`, not `"Azərbaycan Supermarket MMC"`. `null` if not printed. |
| `date` | Purchase date, `yyyy-MM-dd`. `null` if not printed. |
| `currency` | ISO code (`AZN`, `GBP`, `EUR`…). |
| `total` | Final amount paid, as a string with two decimals: `"12.40"`. |
| `items` | Every purchased product, in printed order. |
| `items[].total` | Line total as printed (quantity × unit price), two decimals. |
| `items[].quantity` | Count if printed; `1` for items sold by weight. |
| `items[].name` | Name as printed on the paper. OCR typos in the prediction are tolerated by fuzzy matching. |
| Discounts | Separate item with a negative total: `{ "name": "Endirim", "total": "-0.50" }`. |
| Excluded | Subtotal, VAT/ƏDV/НДС, payment method, cash given, change, bonus/loyalty points, cashier, fiscal and tax IDs. |

## How scoring works

- **Merchant**: case- and accent-insensitive; containment counts ("BRAVO SUPERMARKET" matches "Bravo").
- **Date, total, currency**: exact.
- **Missing vs hallucinated**: if the label is `null`, the prediction must be empty too. Inventing a value counts as wrong.
- **Items**: one-to-one matching on exact amount plus name similarity ≥ 0.5 (character-bigram Dice). Precision, recall and F1 are micro-averaged over all line items.
- **Fully correct**: every field right and every item matched, with nothing extra.
- **Items sum to total**: share of predictions that pass the SDK's own runtime consistency check.
- **Errors** (e.g. receipt too long for the model's context window) count as wrong on every field.

## Dataset

Aim for at least 50 receipts with a spread of shops, languages (Azerbaijani, Russian, English), lengths and print quality. Small datasets give noisy percentages: with 20 receipts, one receipt is 5 points.
