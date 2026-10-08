import XCTest
@testable import DeclutterCore

final class FileScannerTests: XCTestCase {
    private let fileSystem = SystemFileSystem()

    func testScannerIgnoreRules() throws {
        let root = try TemporaryDirectory()
        try root.writeFile("keep.pdf", contents: "hello")
        try root.writeFile("download.pdf", contents: "pdf")
        try root.writeFile("partial-notes.txt", contents: "notes")
        try root.writeFile("photo.JPG", contents: "img")
        try root.writeFile("README", contents: "readme")
        try root.writeFile("archive.tar.gz", contents: "gz")
        try root.writeFile(".secret.txt", contents: "hidden")
        try root.writeFile(".DS_Store", contents: "store")
        try root.writeFile(".localized", contents: "loc")
        try root.writeFile("Sub/nested.txt", contents: "nested")
        try root.writeFile("file.crdownload")
        try root.writeFile("file.download")
        try root.writeFile("file.part")
        try root.writeFile("file.partial")
        try root.writeFile("file.tmp")
        try root.writeFile("file.opdownload")
        try root.writeFile("~$Budget.xlsx")
        try root.writeFile(".com.google.Chrome.abc123")
        let keep = root.url.appendingPathComponent("keep.pdf")
        try root.symlink(named: "link.txt", to: keep)
        try root.symlink(named: "dirlink", to: root.url.appendingPathComponent("Sub"))
        try writeAlias(named: "alias-file", to: keep, in: root)
        var flagged = try root.writeFile("flagged.txt", contents: "hidden-flag")
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try flagged.setResourceValues(hiddenValues)
        try root.writeFile("Widget.app/Contents/Info.plist", contents: "plist")

        let names = Set(try FileScanner(fileSystem: fileSystem).scanAll(source: root.url).map(\.name))

        XCTAssertEqual(
            names,
            ["README", "Widget.app", "archive.tar.gz", "download.pdf", "keep.pdf", "partial-notes.txt", "photo.JPG"]
        )
    }

    func testScannerReadsBatchedMetadata() throws {
        let root = try TemporaryDirectory()
        try root.writeFile("keep.pdf", contents: "hello")
        let snapshots = try FileScanner(fileSystem: fileSystem).scanAll(source: root.url)
        let pdf = try XCTUnwrap(snapshots.first { $0.name == "keep.pdf" })
        XCTAssertEqual(pdf.ext, "pdf")
        XCTAssertEqual(pdf.nameWithoutExt, "keep")
        XCTAssertEqual(pdf.size, 5)
        XCTAssertNotNil(pdf.created)
        XCTAssertNotNil(pdf.modified)
        XCTAssertNotNil(pdf.utType)
        XCTAssertFalse(pdf.isDirectory)
        XCTAssertFalse(pdf.isSymlink)
        XCTAssertFalse(pdf.isHidden)
    }

    func testScannerRequestsResourceKeysInOneBatchAndDoesNotRecurse() throws {
        let recorder = KeyRecordingFileSystem()
        _ = try FileScanner(fileSystem: recorder).scanAll(source: URL(fileURLWithPath: "/source"))
        XCTAssertEqual(recorder.directoryListings, 1)
        XCTAssertEqual(Set(recorder.directoryKeys), Set(FileScanner.resourceKeys))
        XCTAssertEqual(recorder.attributeCalls, 1)
        XCTAssertEqual(recorder.attributeKeys, Set(FileScanner.resourceKeys))
    }

    func testScanStreamMatchesScanAll() async throws {
        let root = try TemporaryDirectory()
        try root.writeFile("b.txt")
        try root.writeFile("a.txt")
        let scanner = FileScanner(fileSystem: fileSystem)
        let scanned = try scanner.scanAll(source: root.url).map(\.name)
        var streamed: [String] = []
        for await snapshot in scanner.scan(source: root.url) {
            streamed.append(snapshot.name)
        }
        XCTAssertEqual(streamed, scanned)
        XCTAssertEqual(scanned, ["a.txt", "b.txt"])
    }

    func testScanThrowsWhenSourceIsMissing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        XCTAssertThrowsError(try FileScanner(fileSystem: fileSystem).scanAll(source: missing))
    }

    private func writeAlias(named name: String, to target: URL, in root: TemporaryDirectory) throws {
        let bookmark = try target.bookmarkData(
            options: [.suitableForBookmarkFile],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmark, to: root.url.appendingPathComponent(name))
    }
}

private final class KeyRecordingFileSystem: FileSystemProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var directoryListings = 0
    private(set) var directoryKeys: [URLResourceKey] = []
    private(set) var attributeCalls = 0
    private(set) var attributeKeys: Set<URLResourceKey> = []

    func contentsOfDirectory(at url: URL, including keys: [URLResourceKey]) throws -> [URL] {
        lock.lock()
        directoryListings += 1
        directoryKeys = keys
        lock.unlock()
        return [url.appendingPathComponent("notes.txt")]
    }

    func attributes(of url: URL, keys: Set<URLResourceKey>) throws -> FileAttributes {
        lock.lock()
        attributeCalls += 1
        attributeKeys = keys
        lock.unlock()
        return FileAttributes(
            name: "notes.txt",
            size: 1,
            created: nil,
            modified: nil,
            isDirectory: false,
            isSymlink: false,
            isAlias: false,
            isHidden: false,
            isPackage: false,
            fileIdentifier: nil,
            typeIdentifier: nil
        )
    }

    func fileExists(at url: URL) -> Bool { false }

    func createDirectory(at url: URL) throws {}

    func moveItem(at source: URL, to destination: URL) throws {}

    func trashItem(at url: URL) throws -> URL { url }
}
