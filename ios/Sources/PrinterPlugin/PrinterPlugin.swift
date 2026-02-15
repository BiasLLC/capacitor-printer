import Foundation
import Capacitor

@objc(PrinterPlugin)
public class PrinterPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "7.3.1"
    public let identifier = "PrinterPlugin"
    public let jsName = "Printer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "printBase64", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "printFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "printHtml", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "printHtmlAsPdf", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareHtmlAsPdf", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "printPdf", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = Printer()

    @objc func printBase64(_ call: CAPPluginCall) {
        guard let data = call.getString("data") else {
            call.reject("data is required")
            return
        }

        guard let mimeType = call.getString("mimeType") else {
            call.reject("mimeType is required")
            return
        }

        let name = call.getString("name") ?? "Document"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.implementation.printBase64(
                    data: data,
                    mimeType: mimeType,
                    name: name,
                    presentingViewController: self.bridge?.viewController
                )
                call.resolve()
            } catch {
                call.reject("Failed to print base64 data: \(error.localizedDescription)")
            }
        }
    }

    @objc func shareHtmlAsPdf(_ call: CAPPluginCall) {
        guard let html = call.getString("html") else {
            call.reject("html is required")
            return
        }
        guard let pageWidth = call.getDouble("pageWidth") else {
            call.reject("pageWidth is required (mm)")
            return
        }
        guard let pageHeight = call.getDouble("pageHeight") else {
            call.reject("pageHeight is required (mm)")
            return
        }
        guard let marginTop = call.getDouble("marginTop") else {
            call.reject("marginTop is required (mm)")
            return
        }
        guard let marginBottom = call.getDouble("marginBottom") else {
            call.reject("marginBottom is required (mm)")
            return
        }
        guard let marginLeft = call.getDouble("marginLeft") else {
            call.reject("marginLeft is required (mm)")
            return
        }
        guard let marginRight = call.getDouble("marginRight") else {
            call.reject("marginRight is required (mm)")
            return
        }
        
        let name = call.getString("name") ?? "Document"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.implementation.shareHtmlAsPdf(
                html: html,
                name: name,
                pageWidthMM: pageWidth,
                pageHeightMM: pageHeight,
                marginTopMM: marginTop,
                marginBottomMM: marginBottom,
                marginLeftMM: marginLeft,
                marginRightMM: marginRight,
                presentingViewController: self.bridge?.viewController
            ) { result in
                switch result {
                case .success:
                    call.resolve()
                case .failure(let error):
                    call.reject("Share failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func printHtmlAsPdf(_ call: CAPPluginCall) {
        guard let html = call.getString("html") else {
            call.reject("html is required")
            return
        }
        guard let pageWidth = call.getDouble("pageWidth") else {
            call.reject("pageWidth is required (mm)")
            return
        }
        guard let pageHeight = call.getDouble("pageHeight") else {
            call.reject("pageHeight is required (mm)")
            return
        }
        guard let marginTop = call.getDouble("marginTop") else {
            call.reject("marginTop is required (mm)")
            return
        }
        guard let marginBottom = call.getDouble("marginBottom") else {
            call.reject("marginBottom is required (mm)")
            return
        }
        guard let marginLeft = call.getDouble("marginLeft") else {
            call.reject("marginLeft is required (mm)")
            return
        }
        guard let marginRight = call.getDouble("marginRight") else {
            call.reject("marginRight is required (mm)")
            return
        }
        
        let name = call.getString("name") ?? "Document"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.implementation.printHtmlAsPdf(
                html: html,
                name: name,
                pageWidthMM: pageWidth,
                pageHeightMM: pageHeight,
                marginTopMM: marginTop,
                marginBottomMM: marginBottom,
                marginLeftMM: marginLeft,
                marginRightMM: marginRight,
                presentingViewController: self.bridge?.viewController
            ) { result in
                switch result {
                case .success:
                    call.resolve()
                case .failure(let error):
                    call.reject("Print failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func printFile(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }

        let name = call.getString("name") ?? "Document"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.implementation.printFile(
                    path: path,
                    name: name,
                    presentingViewController: self.bridge?.viewController
                )
                call.resolve()
            } catch {
                call.reject("Failed to print file: \(error.localizedDescription)")
            }
        }
    }

    @objc func printHtml(_ call: CAPPluginCall) {
        guard let html = call.getString("html") else {
            call.reject("html is required")
            return
        }
        let name = call.getString("name") ?? "Document"

        // Optional page dimensions in mm
        let pageWidth: Double? = call.getDouble("pageWidth")
        let pageHeight: Double? = call.getDouble("pageHeight")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.implementation.printHtml(
                    html: html,
                    name: name,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    presentingViewController: self.bridge?.viewController
                )
                call.resolve()
            } catch {
                call.reject("Failed to print HTML: \(error.localizedDescription)")
            }
        }
    }

    @objc func printPdf(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("path is required")
            return
        }

        let name = call.getString("name") ?? "Document"

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.implementation.printPdf(
                    path: path,
                    name: name,
                    presentingViewController: self.bridge?.viewController
                )
                call.resolve()
            } catch {
                call.reject("Failed to print PDF: \(error.localizedDescription)")
            }
        }
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }
}
