import Foundation
import XCTest
@testable import DownloadOrganizerCore

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadOrganizer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func writeFile(_ relativePath: String, contents: String = "x") throws -> URL {
        let fileURL = relativePath.split(separator: "/").reduce(url) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func symlink(named name: String, to destination: URL) throws -> URL {
        let linkURL = url.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: destination)
        return linkURL
    }
}

func makeSnapshot(
    named name: String,
    in directory: URL = URL(fileURLWithPath: "/Downloads"),
    utType: String? = nil,
    size: Int64 = 1,
    created: Date? = nil,
    modified: Date? = nil
) -> FileSnapshot {
    let url = directory.appendingPathComponent(name)
    let ext = url.pathExtension
    return FileSnapshot(
        url: url,
        name: name,
        nameWithoutExt: ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent,
        ext: ext,
        utType: utType,
        size: size,
        created: created,
        modified: modified,
        fileID: nil,
        isDirectory: false,
        isSymlink: false,
        isHidden: false,
        isPackage: false
    )
}

func makeCategory(
    name: String,
    extensions: [String],
    destination: String = "Sorted",
    priority: Int = 0,
    enabled: Bool = true,
    isCatchAll: Bool = false,
    matchCase: Bool = false,
    op: Operator = .isOneOf,
    value: String? = nil
) -> DownloadOrganizerCore.Category {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let rule: RuleNode = isCatchAll
        ? .group(.and, [])
        : .condition(Condition(field: .extension_, op: op, value: value, values: extensions, matchCase: matchCase))
    return Category(
        name: name,
        iconSymbol: "folder",
        destination: .relative(destination),
        enabled: enabled,
        priority: priority,
        rule: rule,
        isCatchAll: isCatchAll,
        createdAt: now,
        updatedAt: now
    )
}
