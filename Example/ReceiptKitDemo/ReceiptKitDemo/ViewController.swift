//
//  ViewController.swift
//  ReceiptKitDemo
//
//  Created by Nazrin on 21.10.26.
//

import ReceiptKit
import ReceiptKitUI
import UIKit

final class ViewController: UIViewController, ReceiptCaptureViewControllerDelegate {
    private let output = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let button = UIButton(configuration: .filled())
        button.configuration?.title = "Scan receipt"
        button.addAction(UIAction { [weak self] _ in self?.scan() }, for: .touchUpInside)

        output.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        output.isEditable = false

        let stack = UIStackView(arrangedSubviews: [button, output])
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

    func receiptCapture(_ controller: ReceiptCaptureViewController, didFinishWith result: ReceiptScanResult) {
        controller.dismiss(animated: true)
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

