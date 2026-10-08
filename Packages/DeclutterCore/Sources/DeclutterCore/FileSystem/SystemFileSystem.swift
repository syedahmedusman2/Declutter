import Foundation
import UniformTypeIdentifiers

public struct SystemFileSystem: FileSystemProviding {
    public init() {}

    public func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )
    }

    public func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        let values = try url.resourceValues(forKeys: keys)
        return FileAttributes(
            name: values.name ?? url.lastPathComponent,
            size: Int64(values.fileSize ?? 0),
            created: values.creationDate,
            modified: values.contentModificationDate,
            isDirectory: values.isDirectory ?? false,
            isSymlink: values.isSymbolicLink ?? false,
            isAlias: values.isAliasFile ?? false,
            isHidden: values.isHidden ?? false,
            isPackage: values.isPackage ?? false,
            fileIdentifier: Self.fileIdentifier(from: values),
            typeIdentifier: values.contentType?.identifier
        )
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func trashItem(at url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }
        return result as URL
    }

    private static func fileIdentifier(from values: URLResourceValues) -> String? {
        guard let identifier = values.fileResourceIdentifier else { return nil }
        return String(describing: identifier)
    }
}
