import Foundation

public struct ScanOptions: Sendable, Equatable {
    public var includeHidden: Bool
    public var includeLinks: Bool
    public var ignoreSystemFiles: Bool
    public var ignoreTemporaryFiles: Bool
    public var ignoreDirectories: Bool

    public init(
        includeHidden: Bool = false,
        includeLinks: Bool = false,
        ignoreSystemFiles: Bool = true,
        ignoreTemporaryFiles: Bool = true,
        ignoreDirectories: Bool = true
    ) {
        self.includeHidden = includeHidden
        self.includeLinks = includeLinks
        self.ignoreSystemFiles = ignoreSystemFiles
        self.ignoreTemporaryFiles = ignoreTemporaryFiles
        self.ignoreDirectories = ignoreDirectories
    }
}

public struct FileScanner: Sendable {
    static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .contentTypeKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isAliasFileKey,
        .isHiddenKey,
        .isPackageKey,
        .fileResourceIdentifierKey,
    ]

    private static let systemFileNames: Set<String> = [".ds_store", ".localized"]
    private static let temporaryExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "opdownload",
    ]

    private let fileSystem: any FileSystemProviding

    public init(fileSystem: any FileSystemProviding) {
        self.fileSystem = fileSystem
    }

    /// Enumerates one directory level. Subfolders, packages, and links are never entered.
    public func scan(source: URL, options: ScanOptions = ScanOptions()) -> AsyncStream<FileSnapshot> {
        let scanner = self
        return AsyncStream { continuation in
            let task = Task {
                if let snapshots = try? scanner.scanAll(source: source, options: options) {
                    for snapshot in snapshots {
                        if Task.isCancelled { break }
                        continuation.yield(snapshot)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func scanAll(source: URL, options: ScanOptions = ScanOptions()) throws -> [FileSnapshot] {
        let children = try fileSystem.contentsOfDirectory(at: source, including: Self.resourceKeys)
        let keySet = Set(Self.resourceKeys)
        var snapshots: [FileSnapshot] = []
        snapshots.reserveCapacity(children.count)
        for child in children {
            do {
                let attributes = try fileSystem.attributes(of: child, keys: keySet)
                if let snapshot = makeSnapshot(url: child, attributes: attributes, options: options) {
                    snapshots.append(snapshot)
                }
            } catch {
                continue
            }
        }
        snapshots.sort { $0.name < $1.name }
        return snapshots
    }

    private func makeSnapshot(url: URL, attributes: FileAttributes, options: ScanOptions) -> FileSnapshot? {
        guard shouldInclude(attributes, name: url.lastPathComponent, options: options) else { return nil }
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

    private func shouldInclude(_ attributes: FileAttributes, name: String, options: ScanOptions) -> Bool {
        if attributes.isSymlink || attributes.isAlias {
            if !options.includeLinks { return false }
        }
        if attributes.isDirectory && !attributes.isPackage && options.ignoreDirectories {
            return false
        }
        if !options.includeHidden && (attributes.isHidden || name.hasPrefix(".")) {
            return false
        }
        if options.ignoreSystemFiles && Self.systemFileNames.contains(name.lowercased()) {
            return false
        }
        if options.ignoreTemporaryFiles && Self.isTemporaryDownload(name) {
            return false
        }
        return true
    }

    public static func isTemporaryDownload(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.hasPrefix("~$") { return true }
        if lowered.hasPrefix(".com.google.chrome.") { return true }
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        return temporaryExtensions.contains(ext)
    }
}
