import XCTest
@testable import DownloadOrganizerCore

final class PermissionManagerTests: XCTestCase {
    func testCreateResolveRefreshStaleAndRevoke() throws {
        let store = InMemoryBookmarkStore()
        let scope = FakeSecurityScope()
        let manager = PermissionManager(store: store)
        let folder = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true)

        let created = try manager.createBookmark(for: folder)
        let resolved = try manager.resolve(created, scope: scope)
        XCTAssertEqual(resolved.url, folder)
        XCTAssertEqual(resolved.bookmarkData, created)
        XCTAssertFalse(resolved.didRefreshStaleBookmark)
        XCTAssertEqual(scope.started, [folder])

        store.markStale(created)
        let refreshed = try manager.resolve(created, scope: scope)
        XCTAssertTrue(refreshed.didRefreshStaleBookmark)
        XCTAssertEqual(refreshed.url, folder)
        XCTAssertNotEqual(refreshed.bookmarkData, created)

        let second = try manager.resolve(refreshed.bookmarkData, scope: scope)
        XCTAssertFalse(second.didRefreshStaleBookmark)
        XCTAssertEqual(second.bookmarkData, refreshed.bookmarkData)

        store.revoke(created)
        XCTAssertThrowsError(try manager.resolve(created, scope: scope)) { error in
            XCTAssertEqual(error as? PermissionError, .revoked)
        }

        scope.allowAccess = false
        XCTAssertThrowsError(try manager.resolve(refreshed.bookmarkData, scope: scope)) { error in
            XCTAssertEqual(error as? PermissionError, .revoked)
        }
    }

    func testSourceFolderBookmarkRoundTrip() throws {
        let root = try TemporaryDirectory()
        let store = SourceFolderFileStore(fileURL: root.url.appendingPathComponent("Config/source-folder.json"))
        XCTAssertNil(try store.load())

        let folder = SourceFolder(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            displayName: "Downloads",
            bookmarkData: Data("bookmark".utf8),
            ruleSetID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            mode: .existingOnly,
            isActive: true
        )
        try store.save(folder)
        XCTAssertEqual(try store.load(), folder)

        let newer = SourceFolder(
            displayName: "Future",
            bookmarkData: nil,
            mode: .newOnly,
            isActive: false
        )
        var encoded = try JSONEncoder().encode(newer)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json["schemaVersion"] = SchemaVersion.current + 1
        encoded = try JSONSerialization.data(withJSONObject: json)
        try encoded.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(
                error as? SourceFolderStoreError,
                .newerSchema(found: SchemaVersion.current + 1, supported: SchemaVersion.current)
            )
        }
    }
}

private final class InMemoryBookmarkStore: BookmarkStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [Data: Record] = [:]

    struct Record {
        var url: URL
        var isStale: Bool
        var isRevoked: Bool
    }

    func bookmarkData(for url: URL) throws -> Data {
        let data = Data(UUID().uuidString.utf8)
        lock.lock()
        records[data] = Record(url: url, isStale: false, isRevoked: false)
        lock.unlock()
        return data
    }

    func resolveBookmark(_ data: Data) throws -> BookmarkResolution {
        lock.lock()
        let record = records[data]
        lock.unlock()
        guard let record, !record.isRevoked else { throw BookmarkStoreError.revoked }
        return BookmarkResolution(url: record.url, isStale: record.isStale)
    }

    func markStale(_ data: Data) {
        lock.lock()
        records[data]?.isStale = true
        lock.unlock()
    }

    func revoke(_ data: Data) {
        lock.lock()
        records[data]?.isRevoked = true
        lock.unlock()
    }
}

private final class FakeSecurityScope: SecurityScopeControlling, @unchecked Sendable {
    var allowAccess = true
    private let lock = NSLock()
    private var _started: [URL] = []
    var started: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _started
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.lock()
        _started.append(url)
        lock.unlock()
        return allowAccess
    }

    func stopAccessing(_ url: URL) {}
}
