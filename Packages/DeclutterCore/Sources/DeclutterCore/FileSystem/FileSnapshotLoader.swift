import Foundation

public struct FileSnapshotLoader: Sendable {
    private let fileSystem: any FileSystemProviding

    public init(fileSystem: any FileSystemProviding) {
        self.fileSystem = fileSystem
    }

    /// Reads metadata for one file the user picked. Ignore rules are not applied.
    public func load(url: URL) throws -> FileSnapshot {
        let attributes = try fileSystem.attributes(of: url, keys: Set(FileScanner.resourceKeys))
        let name = url.lastPathComponent
        let ext = url.pathExtension
        let nameWithoutExt = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        return FileSnapshot(
            url: url,
            name: name,
            nameWithoutExt: nameWithoutExt,
            ext: ext,
            utType: attributes.typeIdentifier,
            size: attributes.size,
            created: attributes.created,
            modified: attributes.modified,
            fileID: attributes.fileIdentifier,
            isDirectory: attributes.isDirectory,
            isSymlink: attributes.isSymlink,
            isHidden: attributes.isHidden,
            isPackage: attributes.isPackage
        )
    }
}
