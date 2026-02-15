import Foundation
import UIKit
import WebKit

// MARK: - PDF Print Support

/// Page renderer that enforces exact page dimensions via KVC.
/// KVC on paperRect/printableRect is reliable when generating PDFs
/// via UIGraphicsBeginPDFContextToData.
private class SizedPageRenderer: UIPrintPageRenderer {
    
    init(pageSize: CGSize) {
        super.init()
        let rect = CGRect(origin: .zero, size: pageSize)
        // Native margins are zero — CSS @page margins are authoritative
        setValue(NSValue(cgRect: rect), forKey: "paperRect")
        setValue(NSValue(cgRect: rect), forKey: "printableRect")
    }
}

/// Associated object key for delegate lifetime management
private var pdfDelegateKey: UInt8 = 0

/// Navigation delegate that waits for HTML load + font readiness,
/// generates a PDF at exact page dimensions, then prints it.
private class PDFPrintDelegate: NSObject, WKNavigationDelegate {
    
    private weak var webView: WKWebView?
    private let pageSize: CGSize
    private let jobName: String
    private weak var presentingViewController: UIViewController?
    private let completion: (Result<Void, Error>) -> Void
    
    enum PDFPrintError: Error, LocalizedError {
        case pdfGenerationFailed
        case noPages
        case printingNotAvailable
        case noViewController
        
        var errorDescription: String? {
            switch self {
            case .pdfGenerationFailed: return "Failed to generate PDF from HTML"
            case .noPages: return "Document produced zero pages"
            case .printingNotAvailable: return "Printing is not available"
            case .noViewController: return "No presenting view controller"
            }
        }
    }
    
    init(
        webView: WKWebView,
        pageSize: CGSize,
        jobName: String,
        presentingViewController: UIViewController?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.webView = webView
        self.pageSize = pageSize
        self.jobName = jobName
        self.presentingViewController = presentingViewController
        self.completion = completion
        super.init()
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForFonts(webView: webView)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
    
    // MARK: - Font Readiness
    
    private func waitForFonts(webView: WKWebView) {
        let script = """
        (async function() {
            if (document.fonts && document.fonts.ready) {
                await document.fonts.ready;
            }
            return true;
        })()
        """
        
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                NSLog("[Printer] Font readiness check failed: %@, proceeding", error.localizedDescription)
            }
            DispatchQueue.main.async {
                self.generateAndPrint()
            }
        }
    }
    
    // MARK: - PDF Generation + Print
    
    private func generateAndPrint() {
        guard let webView = self.webView else {
            finish(.failure(PDFPrintError.pdfGenerationFailed))
            return
        }
        
        guard UIPrintInteractionController.isPrintingAvailable else {
            finish(.failure(PDFPrintError.printingNotAvailable))
            return
        }
        
        guard let viewController = presentingViewController else {
            finish(.failure(PDFPrintError.noViewController))
            return
        }
        
        // 1. Get the web view's print formatter
        let printFormatter = webView.viewPrintFormatter()
        
        // 2. Create renderer — native margins are zero, CSS handles margins
        let renderer = SizedPageRenderer(pageSize: pageSize)
        renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
        
        // 3. Trigger pagination with length:1, then read actual page count
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        let pageCount = renderer.numberOfPages
        
        guard pageCount > 0 else {
            finish(.failure(PDFPrintError.noPages))
            return
        }
        
        // 4. Generate PDF data
        let pageBounds = CGRect(origin: .zero, size: pageSize)
        let pdfData = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(pdfData, pageBounds, [
            kCGPDFContextTitle as String: jobName
        ])
        
        for pageIndex in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: pageIndex, in: pageBounds)
        }
        
        UIGraphicsEndPDFContext()
        
        guard pdfData.length > 0 else {
            finish(.failure(PDFPrintError.pdfGenerationFailed))
            return
        }
        
        // 5. Print the PDF
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printingItem = pdfData as Data
        printController.printFormatter = nil
        printController.printPageRenderer = nil
        
        let handler: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, error in
            if let error = error {
                self?.finish(.failure(error))
            } else {
                self?.finish(.success(()))
            }
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            let rect = CGRect(
                x: viewController.view.bounds.midX - 150,
                y: viewController.view.bounds.midY - 200,
                width: 300, height: 400
            )
            printController.present(from: rect, in: viewController.view, animated: true, completionHandler: handler)
        } else {
            printController.present(animated: true, completionHandler: handler)
        }
    }
    
    // MARK: - Cleanup
    
    private func finish(_ result: Result<Void, Error>) {
        if let webView = webView {
            objc_setAssociatedObject(webView, &pdfDelegateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            webView.removeFromSuperview()
        }
        webView = nil
        completion(result)
    }
}

@objc public class Printer: NSObject {

    enum PrinterError: Error {
        case invalidBase64Data
        case fileNotFound
        case unsupportedMimeType
        case printingNotAvailable
        case invalidData
    }

    /// Print base64 encoded data
    public func printBase64(
        data: String,
        mimeType: String,
        name: String,
        presentingViewController: UIViewController?
    ) throws {
        // Decode base64 data
        guard let decodedData = Data(base64Encoded: data) else {
            throw PrinterError.invalidBase64Data
        }

        // Create printable item based on MIME type
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = name
        printInfo.outputType = .general

        var printFormatter: UIPrintFormatter?
        var printItem: Any?

        switch mimeType.lowercased() {
        case "application/pdf":
            printInfo.outputType = .general
            printItem = decodedData

        case "image/jpeg", "image/jpg", "image/png", "image/gif", "image/heic", "image/heif":
            printInfo.outputType = .photo
            if let image = UIImage(data: decodedData) {
                printItem = image
            } else {
                throw PrinterError.invalidData
            }

        default:
            throw PrinterError.unsupportedMimeType
        }

        try presentPrintController(
            printInfo: printInfo,
            printFormatter: printFormatter,
            printItem: printItem,
            presentingViewController: presentingViewController
        )
    }

    /// Print file from path
    public func printFile(
        path: String,
        name: String,
        presentingViewController: UIViewController?
    ) throws {
        // Convert path to URL
        var fileURL: URL

        if path.hasPrefix("file://") {
            fileURL = URL(fileURLWithPath: String(path.dropFirst(7)))
        } else {
            fileURL = URL(fileURLWithPath: path)
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PrinterError.fileNotFound
        }

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = name
        printInfo.outputType = .general

        try presentPrintController(
            printInfo: printInfo,
            printFormatter: nil,
            printItem: fileURL,
            presentingViewController: presentingViewController
        )
    }

    /// Print HTML content with optional custom page dimensions
    public func printHtml(
        html: String,
        name: String,
        pageWidth: Double? = nil,
        pageHeight: Double? = nil,
        presentingViewController: UIViewController?
    ) throws {
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = name
        printInfo.outputType = .general

        // Create HTML formatter
        let formatter = UIMarkupTextPrintFormatter(markupText: html)

        if let w = pageWidth, let h = pageHeight {
            // Custom page size: use UIPrintPageRenderer to override paper dimensions
            // Convert mm to points (1mm = 72/25.4 points)
            let mmToPoints = 72.0 / 25.4
            let widthPt = w * mmToPoints
            let heightPt = h * mmToPoints
            let paperRect = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)

            let renderer = UIPrintPageRenderer()
            renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
            renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
            renderer.setValue(NSValue(cgRect: paperRect), forKey: "printableRect")

            try presentPrintControllerWithRenderer(
                printInfo: printInfo,
                renderer: renderer,
                presentingViewController: presentingViewController
            )
        } else {
            // Default: let system determine paper size
            try presentPrintController(
                printInfo: printInfo,
                printFormatter: formatter,
                printItem: nil,
                presentingViewController: presentingViewController
            )
        }
    }

    /// Print HTML as a correctly-sized PDF.
    /// CSS @page margins are preserved and authoritative.
    /// Native renderer sets page SIZE only (zero margins).
    /// WebView is sized to full page dimensions.
    public func printHtmlAsPdf(
        html: String,
        name: String,
        pageWidthMM: Double,
        pageHeightMM: Double,
        presentingViewController: UIViewController?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let viewController = presentingViewController else {
            completion(.failure(PDFPrintDelegate.PDFPrintError.noViewController))
            return
        }
        
        let mmToPt = 72.0 / 25.4
        let pageSize = CGSize(
            width: pageWidthMM * mmToPt,
            height: pageHeightMM * mmToPt
        )
        
        // WebView sized to full page — CSS @page margins handle insets
        let config = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: pageSize),
            configuration: config
        )
        webView.isHidden = true
        webView.isOpaque = false
        viewController.view.addSubview(webView)
        
        let delegate = PDFPrintDelegate(
            webView: webView,
            pageSize: pageSize,
            jobName: name,
            presentingViewController: viewController,
            completion: completion
        )
        
        objc_setAssociatedObject(
            webView,
            &pdfDelegateKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Print PDF file
    public func printPdf(
        path: String,
        name: String,
        presentingViewController: UIViewController?
    ) throws {
        // Convert path to URL
        var fileURL: URL

        if path.hasPrefix("file://") {
            fileURL = URL(fileURLWithPath: String(path.dropFirst(7)))
        } else {
            fileURL = URL(fileURLWithPath: path)
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PrinterError.fileNotFound
        }

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = name
        printInfo.outputType = .general

        try presentPrintController(
            printInfo: printInfo,
            printFormatter: nil,
            printItem: fileURL,
            presentingViewController: presentingViewController
        )
    }

    /// Print web view content
    public func printWebView(
        webView: WKWebView,
        name: String,
        presentingViewController: UIViewController?
    ) throws {
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = name
        printInfo.outputType = .general

        let formatter = webView.viewPrintFormatter()

        try presentPrintController(
            printInfo: printInfo,
            printFormatter: formatter,
            printItem: nil,
            presentingViewController: presentingViewController
        )
    }

    // MARK: - Private Helper Methods

    private func presentPrintController(
        printInfo: UIPrintInfo,
        printFormatter: UIPrintFormatter?,
        printItem: Any?,
        presentingViewController: UIViewController?
    ) throws {
        guard UIPrintInteractionController.isPrintingAvailable else {
            throw PrinterError.printingNotAvailable
        }

        guard let viewController = presentingViewController else {
            throw PrinterError.printingNotAvailable
        }

        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo

        if let formatter = printFormatter {
            printController.printFormatter = formatter
        } else if let item = printItem {
            printController.printingItem = item
        }

        // Present print controller
        if UIDevice.current.userInterfaceIdiom == .pad {
            // For iPad, present as popover
            printController.present(
                from: viewController.view.bounds,
                in: viewController.view,
                animated: true,
                completionHandler: nil
            )
        } else {
            // For iPhone, present modally
            printController.present(
                animated: true,
                completionHandler: nil
            )
        }
    }

    /// Present print controller with a custom page renderer (for custom page sizes)
    private func presentPrintControllerWithRenderer(
        printInfo: UIPrintInfo,
        renderer: UIPrintPageRenderer,
        presentingViewController: UIViewController?
    ) throws {
        guard UIPrintInteractionController.isPrintingAvailable else {
            throw PrinterError.printingNotAvailable
        }

        guard let viewController = presentingViewController else {
            throw PrinterError.printingNotAvailable
        }

        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printPageRenderer = renderer

        // Present print controller
        if UIDevice.current.userInterfaceIdiom == .pad {
            printController.present(
                from: viewController.view.bounds,
                in: viewController.view,
                animated: true,
                completionHandler: nil
            )
        } else {
            printController.present(
                animated: true,
                completionHandler: nil
            )
        }
    }
}
