import Foundation

public struct FileSnapshot: Identifiable, Codable, Sendable, Equatable {
    public var schemaVersion: Int = SchemaVersion.current
    public var url: URL
    public var name: String
    public var nameWithoutExt: String
    public var ext: String
    public var utType: String?
    public var size: Int64
    public var created: Date?
    public var modified: Date?
    public var fileID: String?
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var isHidden: Bool
    public var isPackage: Bool

    public var id: URL { url }

    public init(
        url: URL,
        name: String,
        nameWithoutExt: String,
        ext: String,
        utType: String?,
        size: Int64,
        created: Date?,
        modified: Date?,
        fileID: String?,
        isDirectory: Bool,
        isSymlink: Bool,
        isHidden: Bool,
        isPackage: Bool
    ) {
        self.url = url
        self.name = name
        self.nameWithoutExt = nameWithoutExt
        self.ext = ext
        self.utType = utType
        self.size = size
        self.created = created
        self.modified = modified
        self.fileID = fileID
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isHidden = isHidden
        self.isPackage = isPackage
    }
}
