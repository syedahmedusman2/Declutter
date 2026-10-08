import os

/// Loggers for the core package. The subsystem matches `AppBranding.bundleIdentifier`.
public enum CoreLog {
    public static let rules = Logger(subsystem: "com.example.downloadorganizer", category: "rules")
    public static let organizer = Logger(subsystem: "com.example.downloadorganizer", category: "organizer")
    public static let monitor = Logger(subsystem: "com.example.downloadorganizer", category: "monitor")
}
