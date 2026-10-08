import Foundation

public enum ConflictResolution: Sendable, Equatable {
    case ready(URL, renamed: Bool)
    case skip(String)
    case needsDecision(URL)
    case replace(URL)
}

public struct ConflictResolver: Sendable {
    public init() {}

    /// Picks the final URL for one file. `existsOnDisk` and `isReserved` must treat the source URL as free.
    public func resolve(
        source: URL,
        directory: URL,
        fileName: String,
        policy: ConflictPolicy,
        existsOnDisk: (URL) -> Bool,
        isReserved: (URL) -> Bool
    ) -> ConflictResolution {
        let initial = directory.appendingPathComponent(fileName)
        if DestinationPath.sameFile(initial, source) {
            return .skip(OrganizeMessage.alreadyThere)
        }
        let onDisk = existsOnDisk(initial)
        let reserved = isReserved(initial)
        if !onDisk && !reserved {
            return .ready(initial, renamed: false)
        }
        if policy == .replace && onDisk && !reserved {
            return .replace(initial)
        }
        switch policy {
        case .skip:
            return .skip(OrganizeMessage.nameExists)
        case .ask:
            return .needsDecision(initial)
        case .autoRename, .replace:
            return nextFreeName(
                directory: directory,
                fileName: fileName,
                source: source,
                existsOnDisk: existsOnDisk,
                isReserved: isReserved
            )
        }
    }

    public static func renamed(_ fileName: String, index: Int?) -> String {
        guard let index else { return fileName }
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if ext.isEmpty {
            return "\(base) (\(index))"
        }
        return "\(base) (\(index)).\(ext)"
    }

    private func nextFreeName(
        directory: URL,
        fileName: String,
        source: URL,
        existsOnDisk: (URL) -> Bool,
        isReserved: (URL) -> Bool
    ) -> ConflictResolution {
        var index = 1
        while index <= 10_000 {
            let url = directory.appendingPathComponent(Self.renamed(fileName, index: index))
            let taken = !DestinationPath.sameFile(url, source) && (existsOnDisk(url) || isReserved(url))
            if !taken {
                return .ready(url, renamed: true)
            }
            index += 1
        }
        return .skip(OrganizeMessage.tooManyNames)
    }
}
