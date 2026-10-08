import Foundation

public enum RuleValueParsing {
    public static func integer(from raw: String?) -> Int64? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(trimmed)
    }

    public static func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: trimmed) { return date }

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: trimmed)
    }

    public static func format(date: Date) -> String {
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        return internet.string(from: date)
    }

    /// Inclusive numeric bounds for a `between` condition. Accepts two `values`, or a single `value` split on `...` or `,`.
    public static func integerBounds(value: String?, values: [String]) -> (low: Int64, high: Int64)? {
        let parts = boundParts(value: value, values: values)
        guard parts.count >= 2, let first = integer(from: parts[0]), let second = integer(from: parts[1]) else {
            return nil
        }
        return (min(first, second), max(first, second))
    }

    public static func dateBounds(value: String?, values: [String]) -> (start: Date, end: Date)? {
        let parts = boundParts(value: value, values: values)
        guard parts.count >= 2, let first = date(from: parts[0]), let second = date(from: parts[1]) else {
            return nil
        }
        return first <= second ? (first, second) : (second, first)
    }

    public static func list(value: String?, values: [String]) -> [String] {
        if !values.isEmpty { return values }
        guard let value else { return [] }
        return value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private static func boundParts(value: String?, values: [String]) -> [String] {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if cleaned.count >= 2 { return cleaned }
        guard let value else { return cleaned }
        if value.contains("...") {
            return value.split(separator: "...", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if value.contains(",") {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return cleaned
    }
}
