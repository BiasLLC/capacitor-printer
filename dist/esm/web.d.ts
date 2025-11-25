import { WebPlugin } from '@capacitor/core';
import type { PrintBase64Options, PrintFileOptions, PrintHtmlOptions, PrintOptions, PrintPdfOptions, PrinterPlugin } from './definitions';
export declare class PrinterWeb extends WebPlugin implements PrinterPlugin {
    printBase64(options: PrintBase64Options): Promise<void>;
    printFile(options: PrintFileOptions): Promise<void>;
    printHtml(options: PrintHtmlOptions): Promise<void>;
    printPdf(options: PrintPdfOptions): Promise<void>;
    printWebView(options?: PrintOptions): Promise<void>;
    getPluginVersion(): Promise<{
        version: string;
    }>;
    private printFromUrl;
}
