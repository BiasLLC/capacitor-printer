import XCTest
@testable import PrinterPlugin

class PrinterPluginTests: XCTestCase {
    func testPrinter() {
        // This is a basic test to ensure the plugin compiles
        let implementation = Printer()
        XCTAssertNotNil(implementation)
    }
}
