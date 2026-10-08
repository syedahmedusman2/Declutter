import Foundation

/// Dry run. Reads the filesystem to detect name conflicts and never creates, moves, or trashes anything.
public struct OrganizePlanner: Sendable {
    private let fileSystem: any FileSystemProviding
    private let categories: [Category]
    private let sourceRoot: URL
    private let options: OrganizeOptions
    private let resolver = ConflictResolver()

    public init(
        fileSystem: any FileSystemProviding,
        categories: [Category],
        sourceRoot: URL,
        options: OrganizeOptions = OrganizeOptions()
    ) {
        self.fileSystem = fileSystem
        self.categories = categories
        self.sourceRoot = sourceRoot
        self.options = options
    }

    public func plan(files: [FileSnapshot]) -> [PlannedMove] {
        let engine = ClassificationEngine(categories: categories)
        let destinations = categoryDirectories()
        var reserved: Set<String> = []
        return files.map { file in
            let move = planOne(file, engine: engine, destinations: destinations, reserved: reserved)
            if move.action == .move || move.action == .replace || move.action == .needsDecision {
                reserved.insert(move.proposedURL.standardizedFileURL.path)
            }
            return move
        }
    }

    /// Recomputes one row after the user picks a conflict policy in the preview.
    public func applying(policy: ConflictPolicy, to move: PlannedMove) -> PlannedMove {
        guard move.categoryID != nil, move.action != .blocked else { return move }
        let resolution = resolver.resolve(
            source: move.snapshot.url,
            directory: move.destinationDirectory,
            fileName: move.snapshot.name,
            policy: policy,
            existsOnDisk: diskExists,
            isReserved: { _ in false }
        )
        return Self.makeMove(
            id: move.id,
            file: move.snapshot,
            categoryID: move.categoryID,
            categoryName: move.categoryName,
            ruleSummary: move.ruleSummary,
            directory: move.destinationDirectory,
            policy: policy,
            resolution: resolution
        )
    }

    private func planOne(
        _ file: FileSnapshot,
        engine: ClassificationEngine,
        destinations: [URL],
        reserved: Set<String>
    ) -> PlannedMove {
        if let blocked = safetySkip(file, destinations: destinations) {
            return blocked
        }
        guard let classification = engine.classify(file, sourceRoot: sourceRoot) else {
            return skipped(file, message: OrganizeMessage.noCategory, conflict: .none)
        }
        if DestinationPath.escapesSource(classification.category.destination) {
            return blocked(file, message: OrganizeMessage.outsideSource, directory: file.url.deletingLastPathComponent())
        }
        let directory = classification.explanation.destinationURL.deletingLastPathComponent()
        if let blocked = destinationSafety(file, directory: directory, destinations: destinations) {
            return blocked
        }
        let policy = classification.category.conflictPolicy ?? options.globalConflictPolicy
        let resolution = resolver.resolve(
            source: file.url,
            directory: directory,
            fileName: file.name,
            policy: policy,
            existsOnDisk: diskExists,
            isReserved: { reserved.contains($0.standardizedFileURL.path) }
        )
        return Self.makeMove(
            id: UUID(),
            file: file,
            categoryID: classification.category.id,
            categoryName: classification.category.name,
            ruleSummary: classification.explanation.ruleSummary,
            directory: directory,
            policy: policy,
            resolution: resolution
        )
    }

    private func safetySkip(_ file: FileSnapshot, destinations: [URL]) -> PlannedMove? {
        if file.isSymlink && !options.moveSymlinks {
            return skipped(file, message: OrganizeMessage.link, conflict: .blocked)
        }
        if file.isHidden || file.name.hasPrefix(".") {
            return skipped(file, message: OrganizeMessage.hidden, conflict: .blocked)
        }
        if Self.systemNames.contains(file.name.lowercased()) {
            return skipped(file, message: OrganizeMessage.systemFile, conflict: .blocked)
        }
        if Self.isTemporary(file.name) {
            return skipped(file, message: OrganizeMessage.temporary, conflict: .blocked)
        }
        if destinations.contains(where: { destination in
            !DestinationPath.sameFile(destination, sourceRoot)
                && DestinationPath.contains(file.url, in: destination)
                && !DestinationPath.sameFile(file.url, destination)
        }) {
            return skipped(file, message: OrganizeMessage.insideCategory, conflict: .blocked)
        }
        return nil
    }

    private func destinationSafety(_ file: FileSnapshot, directory: URL, destinations: [URL]) -> PlannedMove? {
        if file.isDirectory && DestinationPath.contains(directory, in: file.url) {
            return blocked(file, message: OrganizeMessage.loop, directory: directory)
        }
        if file.isDirectory && !file.isPackage {
            return skipped(file, message: OrganizeMessage.folder, conflict: .blocked, directory: directory)
        }
        if DestinationPath.sameFile(directory, file.url.deletingLastPathComponent()) {
            return skipped(file, message: OrganizeMessage.sameDirectory, conflict: .blocked, directory: directory)
        }
        if !isPermitted(directory) {
            let message = DestinationPath.contains(directory, in: sourceRoot)
                ? OrganizeMessage.outsideSource
                : OrganizeMessage.outsideScope
            return blocked(file, message: message, directory: directory)
        }
        if destinations.contains(where: { DestinationPath.sameFile($0, file.url) }) {
            return skipped(file, message: OrganizeMessage.categoryFolder, conflict: .blocked, directory: directory)
        }
        return nil
    }

    private func isPermitted(_ directory: URL) -> Bool {
        if DestinationPath.contains(directory, in: sourceRoot) { return true }
        return options.permittedRoots.contains { DestinationPath.contains(directory, in: $0) }
    }

    private func categoryDirectories() -> [URL] {
        categories.map { DestinationPath.directory(for: $0.destination, sourceRoot: sourceRoot) }
    }

    private func diskExists(_ url: URL) -> Bool {
        fileSystem.fileExists(at: url)
    }

    private func skipped(
        _ file: FileSnapshot,
        message: String,
        conflict: ConflictStatus,
        directory: URL? = nil
    ) -> PlannedMove {
        let directory = directory ?? file.url.deletingLastPathComponent()
        return PlannedMove(
            snapshot: file,
            categoryID: nil,
            categoryName: "",
            ruleSummary: "",
            destinationDirectory: directory,
            proposedURL: file.url,
            action: .skip,
            conflict: conflict,
            policy: options.globalConflictPolicy,
            predictedStatus: .skipped,
            message: message
        )
    }

    private func blocked(_ file: FileSnapshot, message: String, directory: URL) -> PlannedMove {
        PlannedMove(
            snapshot: file,
            categoryID: nil,
            categoryName: "",
            ruleSummary: "",
            destinationDirectory: directory,
            proposedURL: directory.appendingPathComponent(file.name),
            action: .blocked,
            conflict: .blocked,
            policy: options.globalConflictPolicy,
            predictedStatus: .failed,
            message: message
        )
    }

    private static func makeMove(
        id: UUID,
        file: FileSnapshot,
        categoryID: UUID?,
        categoryName: String,
        ruleSummary: String,
        directory: URL,
        policy: ConflictPolicy,
        resolution: ConflictResolution
    ) -> PlannedMove {
        switch resolution {
        case .ready(let url, let renamed):
            return PlannedMove(
                id: id,
                snapshot: file,
                categoryID: categoryID,
                categoryName: categoryName,
                ruleSummary: ruleSummary,
                destinationDirectory: directory,
                proposedURL: url,
                action: .move,
                conflict: renamed ? .autoRename : .none,
                policy: policy,
                predictedStatus: .success,
                message: renamed ? "Will be renamed to \(url.lastPathComponent)" : OrganizeMessage.moved
            )
        case .skip(let message):
            return PlannedMove(
                id: id,
                snapshot: file,
                categoryID: categoryID,
                categoryName: categoryName,
                ruleSummary: ruleSummary,
                destinationDirectory: directory,
                proposedURL: directory.appendingPathComponent(file.name),
                action: .skip,
                conflict: message == OrganizeMessage.nameExists ? .skip : .none,
                policy: policy,
                predictedStatus: .skipped,
                message: message
            )
        case .needsDecision(let url):
            return PlannedMove(
                id: id,
                snapshot: file,
                categoryID: categoryID,
                categoryName: categoryName,
                ruleSummary: ruleSummary,
                destinationDirectory: directory,
                proposedURL: url,
                action: .needsDecision,
                conflict: .needsDecision,
                policy: policy,
                predictedStatus: .needsDecision,
                message: OrganizeMessage.needsDecision
            )
        case .replace(let url):
            return PlannedMove(
                id: id,
                snapshot: file,
                categoryID: categoryID,
                categoryName: categoryName,
                ruleSummary: ruleSummary,
                destinationDirectory: directory,
                proposedURL: url,
                action: .replace,
                conflict: .replace,
                policy: policy,
                predictedStatus: .success,
                message: "The existing file will be moved to the Trash"
            )
        }
    }

    private static let systemNames: Set<String> = [".ds_store", ".localized"]
    private static let temporaryExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "opdownload",
    ]

    private static func isTemporary(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.hasPrefix("~$") || lowered.hasPrefix(".com.google.chrome.") { return true }
        return temporaryExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
    }
}
