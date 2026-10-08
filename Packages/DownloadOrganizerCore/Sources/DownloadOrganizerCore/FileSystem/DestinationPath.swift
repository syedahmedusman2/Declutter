import Foundation

enum DestinationPath {
    static func directory(for destination: Destination, sourceRoot: URL) -> URL {
        switch destination {
        case .relative(let relativePath):
            return appending(sourceRoot, relativePath: relativePath)
        case .absolute(let path, _):
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    static func appending(_ root: URL, relativePath: String) -> URL {
        let parts = relativePath.split(separator: "/").map(String.init).filter { part in
            !part.isEmpty && part != "."
        }
        return parts.reduce(root) { partial, part in
            partial.appendingPathComponent(part, isDirectory: true)
        }
    }

    static func escapesSource(_ destination: Destination) -> Bool {
        guard case .relative(let relativePath) = destination else { return false }
        return relativePath.split(separator: "/").contains("..")
    }

    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    /// True when `url` is `root` or a file inside it.
    static func contains(_ url: URL, in root: URL) -> Bool {
        let child = url.standardizedFileURL.path
        let parent = root.standardizedFileURL.path
        if child == parent { return true }
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        return child.hasPrefix(prefix)
    }
}
