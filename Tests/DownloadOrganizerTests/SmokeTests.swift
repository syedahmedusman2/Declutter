import XCTest
@testable import DownloadOrganizer

final class SmokeTests: XCTestCase {
    func testBrandingMatchesBundle() {
        XCTAssertEqual(AppBranding.name, "Download Organizer")
        XCTAssertEqual(AppBranding.bundleIdentifier, "com.example.downloadorganizer")
        XCTAssertEqual(Bundle.main.bundleIdentifier, AppBranding.bundleIdentifier)
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            AppBranding.name
        )
    }
}
