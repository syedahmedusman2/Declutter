import XCTest
@testable import DownloadOrganizerCore

final class SmokeTests: XCTestCase {
    func testCoreModuleLoads() {
        XCTAssertEqual(CoreMarker.moduleName, "DownloadOrganizerCore")
    }
}
