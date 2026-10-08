import Foundation

public struct FileAttributes: Sendable, Equatable {
    public var name: String
    public var size: Int64
    public var created: Date?
    public var modified: Date?
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var isAlias: Bool
    public var isHidden: Bool
    public var isPackage: Bool
    public var fileIdentifier: String?
    public var typeIdentifier: String?

    public init(
        name: String,
        size: Int64,
        created: Date?,
        modified: Date?,
        isDirectory: Bool,
        isSymlink: Bool,
        isAlias: Bool,
        isHidden: Bool,
        isPackage: Bool,
        fileIdentifier: String?,
        typeIdentifier: String?
    ) {
        self.name = name
        self.size = size
        self.created = created
        self.modified = modified
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isAlias = isAlias
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.fileIdentifier = fileIdentifier
        self.typeIdentifier = typeIdentifier
    }
}

public protocol FileSystemProviding: Sendable {
    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL]
    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func trashItem(at url: URL) throws -> URL
    func removeEmptyDirectory(at url: URL) throws
}

extension FileSystemProviding {
    public func removeEmptyDirectory(at url: URL) throws {
        let children = try contentsOfDirectory(at: url, including: [])
        guard children.isEmpty else { return }
        try FileManager.default.removeItem(at: url)
    }
}
