import ReceiptKit
import ReceiptKitEvaluation
import ReceiptKitUI
import UIKit

final class ViewController: UIViewController, ReceiptCaptureViewControllerDelegate {
    private let output = UITextView()
    private let exportButton = UIButton(configuration: .tinted())
    private var lastResult: ReceiptScanResult?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let scanButton = UIButton(configuration: .filled())
        scanButton.configuration?.title = "Scan receipt"
        scanButton.addAction(UIAction { [weak self] _ in self?.scan() }, for: .touchUpInside)

        exportButton.configuration?.title = "Export for evaluation"
        exportButton.isEnabled = false
        exportButton.addAction(UIAction { [weak self] _ in self?.exportFixture() }, for: .touchUpInside)

        output.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        output.isEditable = false

        let buttons = UIStackView(arrangedSubviews: [scanButton, exportButton])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [buttons, output])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func scan() {
        let capture = ReceiptCaptureViewController()
        capture.delegate = self
        capture.modalPresentationStyle = .fullScreen
        present(capture, animated: true)
    }

    // MARK: - Export a labeled fixture

    /// Saves the OCR output plus a draft label as JSON and opens the share sheet
    /// (AirDrop it to your Mac, then put it in Eval/fixtures/ and correct the label).
    private func exportFixture() {
        guard let result = lastResult else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let id = "receipt-" + formatter.string(from: Date())

        do {
            let fixture = ReceiptFixture(draftFrom: result, id: id)
            let data = try FixtureFormat.encoder().encode(fixture)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).json")
            try data.write(to: url, options: .atomic)

            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = exportButton
            present(share, animated: true)
        } catch {
            output.text = "Export failed: \(error)"
        }
    }

    // MARK: - ReceiptCaptureViewControllerDelegate

    func receiptCapture(_ controller: ReceiptCaptureViewController, didFinishWith result: ReceiptScanResult) {
        controller.dismiss(animated: true)
        lastResult = result
        exportButton.isEnabled = true

        let r = result.receipt
        var text = "Merchant: \(r.merchant ?? "—")\nDate: \(r.date.map { "\($0)" } ?? "—")\n"
        text += "Total: \(r.total.map { "\($0.amount) \($0.currencyCode)" } ?? "—")\n\nItems:\n"
        text += r.items.map { "  \($0.quantity)× \($0.name)  \($0.total.amount)" }.joined(separator: "\n")
        text += "\n\nWarnings: \(result.warnings)\n\n--- Raw OCR ---\n"
        text += result.recognizedLines.map(\.text).joined(separator: "\n")
        output.text = text
    }

    func receiptCapture(_ controller: ReceiptCaptureViewController, didFailWith error: any Error) {
        controller.dismiss(animated: true)
        output.text = "Error: \(error)"
    }

    func receiptCaptureDidCancel(_ controller: ReceiptCaptureViewController) {
        controller.dismiss(animated: true)
    }
}
