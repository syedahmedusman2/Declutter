import XCTest
@testable import DeclutterCore

final class SmokeTests: XCTestCase {
    func testCoreModuleLoads() {
        XCTAssertEqual(CoreMarker.moduleName, "DeclutterCore")
    }
}
