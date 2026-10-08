import Foundation

public struct DiagnosticsReport: Sendable, Equatable {
    public var appVersion: String
    public var systemVersion: String
    public var settingsSummary: String
    public var logLines: [String]
    public var history: [HistoryItem]

    public init(
        appVersion: String,
        systemVersion: String,
        settingsSummary: String,
        logLines: [String],
        history: [HistoryItem]
    ) {
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.settingsSummary = settingsSummary
        self.logLines = logLines
        self.history = history
    }
}

public enum DiagnosticsExporter {
    public static func zip(report: DiagnosticsReport, includePaths: Bool) -> Data {
        let version = "app \(report.appVersion)\nsystem \(report.systemVersion)\n"
        let history = report.history.prefix(50).map { line($0, includePaths: includePaths) }.joined(separator: "\n")
        let logs = report.logLines.joined(separator: "\n")
        return ZipArchive.data(files: [
            ("version.txt", Data(version.utf8)),
            ("settings.txt", Data(report.settingsSummary.utf8)),
            ("logs.txt", Data(logs.utf8)),
            ("history.txt", Data(history.utf8))
        ])
    }

    public static func historyLine(_ item: HistoryItem, includePaths: Bool) -> String {
        line(item, includePaths: includePaths)
    }

    private static func line(_ item: HistoryItem, includePaths: Bool) -> String {
        if includePaths {
            return "\(item.status.rawValue) \(item.originalName) \(item.sourcePath) -> \(item.destinationPath)"
        }
        return "\(item.status.rawValue) \(item.originalName)"
    }
}

enum ZipArchive {
    static func data(files: [(String, Data)]) -> Data {
        var locals = Data()
        var central = Data()
        var offset: UInt32 = 0
        for (name, payload) in files {
            let nameData = Data(name.utf8)
            let crc = CRC32.hash(payload)
            let size = UInt32(payload.count)
            var local = Data()
            local.appendU32(0x0403_4B50)
            local.appendU16(20)
            local.appendU16(0)
            local.appendU16(0)
            local.appendU16(0)
            local.appendU16(0)
            local.appendU32(crc)
            local.appendU32(size)
            local.appendU32(size)
            local.appendU16(UInt16(nameData.count))
            local.appendU16(0)
            local.append(nameData)
            local.append(payload)

            var entry = Data()
            entry.appendU32(0x0201_4B50)
            entry.appendU16(20)
            entry.appendU16(20)
            entry.appendU16(0)
            entry.appendU16(0)
            entry.appendU16(0)
            entry.appendU16(0)
            entry.appendU32(crc)
            entry.appendU32(size)
            entry.appendU32(size)
            entry.appendU16(UInt16(nameData.count))
            entry.appendU16(0)
            entry.appendU16(0)
            entry.appendU16(0)
            entry.appendU16(0)
            entry.appendU32(0)
            entry.appendU32(offset)
            entry.append(nameData)
            central.append(entry)
            offset += UInt32(local.count)
            locals.append(local)
        }
        var end = Data()
        end.appendU32(0x0605_4B50)
        end.appendU16(0)
        end.appendU16(0)
        end.appendU16(UInt16(files.count))
        end.appendU16(UInt16(files.count))
        end.appendU32(UInt32(central.count))
        end.appendU32(offset)
        end.appendU16(0)
        var archive = locals
        archive.append(central)
        archive.append(end)
        return archive
    }
}

private enum CRC32 {
    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendU16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendU32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
