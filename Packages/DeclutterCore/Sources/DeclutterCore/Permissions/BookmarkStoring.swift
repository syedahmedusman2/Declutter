import Foundation

public struct BookmarkResolution: Sendable, Equatable {
    public var url: URL
    public var isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public enum BookmarkStoreError: Error, Equatable, Sendable {
    case revoked
    case creationFailed(String)
}

public protocol BookmarkStoring: Sendable {
    func bookmarkData(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> BookmarkResolution
}

public protocol SecurityScopeControlling: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct SystemSecurityScope: SecurityScopeControlling {
    public init() {}

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
