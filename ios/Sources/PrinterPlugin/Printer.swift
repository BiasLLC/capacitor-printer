import WebKit

// MARK: - WKWebView PDF Delegate

private var webViewPDFDelegateKey: UInt8 = 0

@available(iOS 15.0, *)
private class WebViewPDFDelegate: NSObject, WKNavigationDelegate {

    static var activeDelegates: [String: WebViewPDFDelegate] = [:]

    var delegateId: String?
    private weak var webView: WKWebView?
    private let pageSize: CGSize
    private let margins: UIEdgeInsets
    private let jobName: String
    private weak var presentingViewController: UIViewController?
    private let completion: (Result<Void, Error>) -> Void

    init(
        webView: WKWebView,
        pageSize: CGSize,
        margins: UIEdgeInsets,
        jobName: String,
        presentingViewController: UIViewController?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.webView = webView
        self.pageSize = pageSize
        self.margins = margins
        self.jobName = jobName
        self.presentingViewController = presentingViewController
        self.completion = completion
        super.init()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (async function() {
            if (document.fonts && document.fonts.ready) { await document.fonts.ready; }
            await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
            return 'ready';
        })()
        """

        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            self.generatePDF()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
        completion(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        cleanup()
        completion(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        cleanup()
        completion(.failure(NSError(domain: "Printer", code: 5,
            userInfo: [NSLocalizedDescriptionKey: "WebView content process terminated"])))
    }

    // MARK: - PDF Generation

    private func generatePDF() {
        guard let webView = self.webView else {
            cleanup()
            completion(.failure(NSError(domain: "Printer", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "WebView was deallocated"])))
            return
        }

        // Get print formatter from WKWebView — inherits font rendering
        let printFormatter = webView.viewPrintFormatter()

        // Create renderer with page geometry
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)

        let paperRect = CGRect(origin: .zero, size: pageSize)
        let printableRect = paperRect.inset(by: margins)

        renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

        // Generate PDF
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, paperRect, nil)
        renderer.prepare(forDrawingPages: NSMakeRange(0, renderer.numberOfPages))

        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        // Clean up webView before presenting
        self.cleanup()

        // Present the PDF
        self.presentPDF(data: pdfData as Data)
    }

    // MARK: - Print Presentation

    private func presentPDF(data: Data) {
        guard let viewController = self.presentingViewController else {
            cleanup()
            completion(.failure(NSError(domain: "Printer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No presenting view controller"])))
            return
        }

        guard UIPrintInteractionController.isPrintingAvailable else {
            cleanup()
            completion(.failure(NSError(domain: "Printer", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Printing not available"])))
            return
        }

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = jobName
        printInfo.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.printFormatter = nil
        controller.printPageRenderer = nil

        let handler: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, error in
            self?.cleanup()
            if let error = error {
                self?.completion(.failure(error))
            } else {
                self?.completion(.success(()))
            }
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(
                from: viewController.view.bounds,
                in: viewController.view,
                animated: true,
                completionHandler: handler
            )
        } else {
            controller.present(animated: true, completionHandler: handler)
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        if let id = delegateId {
            WebViewPDFDelegate.activeDelegates.removeValue(forKey: id)
        }
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

    /// Print HTML as PDF using WKWebView for full CSS/font support.
    /// Unlike printHtmlAsPdf (which uses UIMarkupTextPrintFormatter),
    /// this method supports @font-face, custom fonts, and full CSS.
    @available(iOS 15.0, *)
    public func printHtmlAsPdfWebView(
        html: String,
        name: String,
        pageWidthMM: Double,
        pageHeightMM: Double,
        marginTopMM: Double,
        marginBottomMM: Double,
        marginLeftMM: Double,
        marginRightMM: Double,
        presentingViewController: UIViewController?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let viewController = presentingViewController else {
            completion(.failure(NSError(domain: "Printer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No presenting view controller"])))
            return
        }

        let mmToPt = 72.0 / 25.4
        let pageW = pageWidthMM * mmToPt
        let pageH = pageHeightMM * mmToPt
        let pageSize = CGSize(width: pageW, height: pageH)
        let margins = UIEdgeInsets(
            top: marginTopMM * mmToPt,
            left: marginLeftMM * mmToPt,
            bottom: marginBottomMM * mmToPt,
            right: marginRightMM * mmToPt
        )

        // Create hidden WKWebView sized to page
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(origin: .zero, size: pageSize), configuration: config)
        webView.isHidden = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        viewController.view.addSubview(webView)

        // Use bundle resource URL so @font-face url("public/fonts/...") resolves
        let baseURL = Bundle.main.resourceURL

        // Set up delegate
        let delegate = WebViewPDFDelegate(
            webView: webView,
            pageSize: pageSize,
            margins: margins,
            jobName: name,
            presentingViewController: viewController,
            completion: completion
        )

        // Retain delegate via static dictionary
        let delegateId = UUID().uuidString
        WebViewPDFDelegate.activeDelegates[delegateId] = delegate
        delegate.delegateId = delegateId

        webView.navigationDelegate = delegate

        // Load HTML with baseURL for font resolution
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    // MARK: - PDF Generation
    
    /// Generate PDF data from HTML at exact page dimensions.
    private func generatePdf(html: String, paperRect: CGRect, printableRect: CGRect) -> Data {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = .zero
        
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")
        
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, paperRect, nil)
        
        renderer.prepare(forDrawingPages: NSMakeRange(0, renderer.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: bounds)
        }
        
        UIGraphicsEndPDFContext()
        return pdfData as Data
    }
    
    /// Print HTML as a correctly-sized PDF.
    public func printHtmlAsPdf(
        html: String,
        name: String,
        pageWidthMM: Double,
        pageHeightMM: Double,
        marginTopMM: Double,
        marginBottomMM: Double,
        marginLeftMM: Double,
        marginRightMM: Double,
        presentingViewController: UIViewController?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let viewController = presentingViewController else {
            completion(.failure(NSError(domain: "Printer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No presenting view controller"])))
            return
        }
        
        let mmToPt = 72.0 / 25.4
        let pageW = pageWidthMM * mmToPt
        let pageH = pageHeightMM * mmToPt
        let mTop = marginTopMM * mmToPt
        let mBottom = marginBottomMM * mmToPt
        let mLeft = marginLeftMM * mmToPt
        let mRight = marginRightMM * mmToPt
        
        let paperRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let printableRect = CGRect(x: mLeft, y: mTop, width: pageW - mLeft - mRight, height: pageH - mTop - mBottom)
        
        let pdfData = generatePdf(html: html, paperRect: paperRect, printableRect: printableRect)
        
        guard pdfData.count > 0 else {
            completion(.failure(NSError(domain: "Printer", code: 2, userInfo: [NSLocalizedDescriptionKey: "PDF generation produced no data"])))
            return
        }
        
        guard UIPrintInteractionController.isPrintingAvailable else {
            completion(.failure(NSError(domain: "Printer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Printing not available"])))
            return
        }
        
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = name
        printInfo.outputType = .general
        
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfData
        controller.printFormatter = nil
        controller.printPageRenderer = nil
        
        let handler: UIPrintInteractionController.CompletionHandler = { _, _, error in
            if let error = error { completion(.failure(error)) }
            else { completion(.success(())) }
        }
        
        DispatchQueue.main.async {
            if UIDevice.current.userInterfaceIdiom == .pad {
                controller.present(from: viewController.view.bounds, in: viewController.view, animated: true, completionHandler: handler)
            } else {
                controller.present(animated: true, completionHandler: handler)
            }
        }
    }
    
    /// Share HTML as a correctly-sized PDF via share sheet.
    public func shareHtmlAsPdf(
        html: String,
        name: String,
        pageWidthMM: Double,
        pageHeightMM: Double,
        marginTopMM: Double,
        marginBottomMM: Double,
        marginLeftMM: Double,
        marginRightMM: Double,
        presentingViewController: UIViewController?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let viewController = presentingViewController else {
            completion(.failure(NSError(domain: "Printer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No presenting view controller"])))
            return
        }
        
        let mmToPt = 72.0 / 25.4
        let pageW = pageWidthMM * mmToPt
        let pageH = pageHeightMM * mmToPt
        let mTop = marginTopMM * mmToPt
        let mBottom = marginBottomMM * mmToPt
        let mLeft = marginLeftMM * mmToPt
        let mRight = marginRightMM * mmToPt
        
        let paperRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let printableRect = CGRect(x: mLeft, y: mTop, width: pageW - mLeft - mRight, height: pageH - mTop - mBottom)
        
        let pdfData = generatePdf(html: html, paperRect: paperRect, printableRect: printableRect)
        
        guard pdfData.count > 0 else {
            completion(.failure(NSError(domain: "Printer", code: 2, userInfo: [NSLocalizedDescriptionKey: "PDF generation produced no data"])))
            return
        }
        
        let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        do {
            try pdfData.write(to: tmpUrl)
        } catch {
            completion(.failure(error))
            return
        }
        
        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(activityItems: [tmpUrl], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            activityVC.completionWithItemsHandler = { _, _, _, error in
                try? FileManager.default.removeItem(at: tmpUrl)
                if let error = error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
            viewController.present(activityVC, animated: true)
        }
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
