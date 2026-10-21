#if canImport(UIKit) && canImport(VisionKit)
import ReceiptKit
import UIKit
import VisionKit

public enum ReceiptCaptureError: Error, Sendable {
    case cameraUnavailable
    case noPageCaptured
}

@MainActor
public protocol ReceiptCaptureViewControllerDelegate: AnyObject {
    func receiptCapture(_ controller: ReceiptCaptureViewController, didFinishWith result: ReceiptScanResult)
    func receiptCapture(_ controller: ReceiptCaptureViewController, didFailWith error: any Error)
    func receiptCaptureDidCancel(_ controller: ReceiptCaptureViewController)
}

/// Drop-in UIKit screen: opens the system document camera, scans the first page,
/// and reports a `ReceiptScanResult` to its delegate. The host presents it and
/// dismisses it from the delegate callbacks.
public final class ReceiptCaptureViewController: UIViewController {
    public weak var delegate: (any ReceiptCaptureViewControllerDelegate)?

    private let scanner: ReceiptScanner
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var hasPresentedCamera = false
    private var scanTask: Task<Void, Never>?

    public init(scanner: ReceiptScanner = ReceiptScanner()) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresentedCamera else { return }
        hasPresentedCamera = true
        presentCamera()
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent { scanTask?.cancel() }
    }

    private func presentCamera() {
        guard VNDocumentCameraViewController.isSupported else {
            delegate?.receiptCapture(self, didFailWith: ReceiptCaptureError.cameraUnavailable)
            return
        }
        let camera = VNDocumentCameraViewController()
        camera.delegate = self
        present(camera, animated: true)
    }

    private func process(_ image: CGImage) {
        activityIndicator.startAnimating()
        scanTask = Task { [weak self, scanner] in
            do {
                let result = try await scanner.scan(image)
                guard let self, !Task.isCancelled else { return }
                self.activityIndicator.stopAnimating()
                self.delegate?.receiptCapture(self, didFinishWith: result)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.activityIndicator.stopAnimating()
                self.delegate?.receiptCapture(self, didFailWith: error)
            }
        }
    }
}

extension ReceiptCaptureViewController: @preconcurrency VNDocumentCameraViewControllerDelegate {
    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)
        guard scan.pageCount > 0, let image = scan.imageOfPage(at: 0).cgImage else {
            delegate?.receiptCapture(self, didFailWith: ReceiptCaptureError.noPageCaptured)
            return
        }
        process(image)
    }

    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        delegate?.receiptCaptureDidCancel(self)
    }

    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: any Error
    ) {
        controller.dismiss(animated: true)
        delegate?.receiptCapture(self, didFailWith: error)
    }
}
#endif
