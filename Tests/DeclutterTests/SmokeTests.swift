import XCTest
@testable import Declutter

final class SmokeTests: XCTestCase {
    func testBrandingMatchesBundle() {
        XCTAssertEqual(AppBranding.name, "Declutter")
        XCTAssertEqual(AppBranding.bundleIdentifier, "com.declutterapp.declutter")
        XCTAssertEqual(Bundle.main.bundleIdentifier, AppBranding.bundleIdentifier)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            AppBranding.name
        )
    }
}
