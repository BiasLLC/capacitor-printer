'use strict';

var core = require('@capacitor/core');

const Printer = core.registerPlugin('Printer', {
    web: () => Promise.resolve().then(function () { return web; }).then((m) => new m.PrinterWeb()),
});

class PrinterWeb extends core.WebPlugin {
    async printBase64(options) {
        const { data, mimeType, name } = options;
        // Convert base64 to blob
        const byteCharacters = atob(data);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: mimeType });
        // Create object URL and print
        const url = URL.createObjectURL(blob);
        await this.printFromUrl(url, name);
        URL.revokeObjectURL(url);
    }
    async printFile(options) {
        const { path, name } = options;
        // On web, we can only print URLs that are accessible
        // This will work for file:// URLs in some browsers or HTTP(S) URLs
        await this.printFromUrl(path, name);
    }
    async printHtml(options) {
        const { html, name } = options;
        // Create a blob URL from the HTML content
        const blob = new Blob([html], { type: 'text/html' });
        const url = URL.createObjectURL(blob);
        await this.printFromUrl(url, name);
        URL.revokeObjectURL(url);
    }
    async printPdf(options) {
        const { path, name } = options;
        // On web, print the PDF URL
        await this.printFromUrl(path, name);
    }
    async printWebView(options) {
        // Set document title for print job name
        const originalTitle = document.title;
        if (options === null || options === void 0 ? void 0 : options.name) {
            document.title = options.name;
        }
        // Trigger browser print dialog
        window.print();
        // Restore original title
        document.title = originalTitle;
    }
    async getPluginVersion() {
        return { version: '7.0.0' };
    }
    async printFromUrl(url, name) {
        return new Promise((resolve, reject) => {
            // Create hidden iframe
            const iframe = document.createElement('iframe');
            iframe.style.position = 'fixed';
            iframe.style.right = '0';
            iframe.style.bottom = '0';
            iframe.style.width = '0';
            iframe.style.height = '0';
            iframe.style.border = 'none';
            // Set up load handler
            iframe.onload = () => {
                try {
                    // Set document title if name provided
                    if (name && iframe.contentDocument) {
                        iframe.contentDocument.title = name;
                    }
                    // Small delay to ensure content is loaded
                    setTimeout(() => {
                        try {
                            // Try to access the iframe's window
                            const iframeWindow = iframe.contentWindow;
                            if (!iframeWindow) {
                                throw new Error('Cannot access iframe window');
                            }
                            // Print the iframe content
                            iframeWindow.focus();
                            iframeWindow.print();
                            // Clean up after a delay
                            setTimeout(() => {
                                document.body.removeChild(iframe);
                                resolve();
                            }, 100);
                        }
                        catch (error) {
                            document.body.removeChild(iframe);
                            reject(error);
                        }
                    }, 100);
                }
                catch (error) {
                    document.body.removeChild(iframe);
                    reject(error);
                }
            };
            iframe.onerror = () => {
                document.body.removeChild(iframe);
                reject(new Error('Failed to load content for printing'));
            };
            // Add iframe to document and set source
            document.body.appendChild(iframe);
            iframe.src = url;
        });
    }
}

var web = /*#__PURE__*/Object.freeze({
    __proto__: null,
    PrinterWeb: PrinterWeb
});

exports.Printer = Printer;
//# sourceMappingURL=plugin.cjs.js.map
