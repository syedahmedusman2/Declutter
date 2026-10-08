import Foundation

/// Single source for the user-visible name and bundle identifier.
/// Keep these values aligned with `APP_DISPLAY_NAME` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
enum AppBranding {
    static let name = "Download Organizer"
    static let bundleIdentifier = "com.example.downloadorganizer"
    /// Keep aligned with `MARKETING_VERSION` in `project.yml`.
    static let version = "0.1.0"
}
