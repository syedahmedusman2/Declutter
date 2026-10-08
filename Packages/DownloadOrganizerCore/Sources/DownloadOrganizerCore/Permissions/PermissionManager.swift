import Foundation

public struct ResolvedBookmark: Sendable, Equatable {
    public var url: URL
    public var bookmarkData: Data
    public var didRefreshStaleBookmark: Bool

    public init(url: URL, bookmarkData: Data, didRefreshStaleBookmark: Bool) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.didRefreshStaleBookmark = didRefreshStaleBookmark
    }
}

public enum PermissionError: Error, Equatable, LocalizedError, Sendable {
    case revoked

    public var errorDescription: String? {
        switch self {
        case .revoked:
            "Access to the folder was revoked. Choose the folder again."
        }
    }
}

public struct PermissionManager: Sendable {
    private let store: any BookmarkStoring

    public init(store: any BookmarkStoring) {
        self.store = store
    }

    public func createBookmark(for url: URL) throws -> Data {
        try store.bookmarkData(for: url)
    }

    /// Resolves a bookmark, refreshes it when stale, and starts security-scoped access.
    /// The caller must call `scope.stopAccessing` with the returned URL.
    public func resolve(_ data: Data, scope: any SecurityScopeControlling) throws -> ResolvedBookmark {
        let resolution: BookmarkResolution
        do {
            resolution = try store.resolveBookmark(data)
        } catch BookmarkStoreError.revoked {
            throw PermissionError.revoked
        }

        guard scope.startAccessing(resolution.url) else {
            throw PermissionError.revoked
        }

        if resolution.isStale {
            do {
                let refreshed = try store.bookmarkData(for: resolution.url)
                return ResolvedBookmark(url: resolution.url, bookmarkData: refreshed, didRefreshStaleBookmark: true)
            } catch {
                scope.stopAccessing(resolution.url)
                throw error
            }
        }

        return ResolvedBookmark(url: resolution.url, bookmarkData: data, didRefreshStaleBookmark: false)
    }
}
