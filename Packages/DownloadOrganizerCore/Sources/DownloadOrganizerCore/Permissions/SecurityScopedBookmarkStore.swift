import Foundation

public struct SecurityScopedBookmarkStore: BookmarkStoring {
    public init() {}

    public func bookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkStoreError.creationFailed(String(describing: error))
        }
    }

    public func resolveBookmark(_ data: Data) throws -> BookmarkResolution {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return BookmarkResolution(url: url, isStale: isStale)
        } catch {
            throw BookmarkStoreError.revoked
        }
    }
}
