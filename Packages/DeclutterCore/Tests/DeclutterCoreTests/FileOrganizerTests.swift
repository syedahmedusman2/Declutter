import XCTest
@testable import DeclutterCore

final class FileOrganizerTests: XCTestCase {
    private let fileSystem = SystemFileSystem()

    func testAutoRename() throws {
        let root = try TemporaryDirectory()
        let category = makeCategory(name: "PDFs", extensions: ["pdf"], destination: "PDFs")
        let organizer = FileOrganizer(fileSystem: fileSystem)
        try root.writeFile("PDFs/report.pdf", contents: "original")

        let first = try move("report.pdf", contents: "one", category: category, organizer: organizer, root: root)
        let second = try move("report.pdf", contents: "two", category: category, organizer: organizer, root: root)
        let third = try move("report.pdf", contents: "three", category: category, organizer: organizer, root: root)

        XCTAssertEqual(first.destinationURL?.lastPathComponent, "report (1).pdf")
        XCTAssertEqual(second.destinationURL?.lastPathComponent, "report (2).pdf")
        XCTAssertEqual(third.destinationURL?.lastPathComponent, "report (3).pdf")
        XCTAssertEqual(first.status, .success)
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("PDFs/report.pdf"), encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("PDFs/report (1).pdf"), encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("PDFs/report (2).pdf"), encoding: .utf8), "two")
        XCTAssertFalse(fileSystem.fileExists(at: root.url.appendingPathComponent("report.pdf")))
    }

    func testAutoRenameForNoExtensionAndMultipleDots() throws {
        let root = try TemporaryDirectory()
        let organizer = FileOrganizer(fileSystem: fileSystem)
        let docs = makeCategory(name: "Text", extensions: [], destination: "Docs")
        try root.writeFile("Docs/README", contents: "old")
        try root.writeFile("Docs/archive.tar.gz", contents: "old-archive")

        let readme = try move("README", contents: "new", category: docs, organizer: organizer, root: root)
        let archive = try move("archive.tar.gz", contents: "new-archive", category: docs, organizer: organizer, root: root)

        XCTAssertEqual(readme.destinationURL?.lastPathComponent, "README (1)")
        XCTAssertEqual(archive.destinationURL?.lastPathComponent, "archive.tar (1).gz")
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("Docs/README"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: root.url.appendingPathComponent("Docs/archive.tar.gz"), encoding: .utf8), "old-archive")
    }

    func testOrganizerCreatesIntermediateDestinationDirectories() throws {
        let root = try TemporaryDirectory()
        let category = makeCategory(name: "Word", extensions: ["docx"], destination: "Documents/Word")
        let organizer = FileOrganizer(fileSystem: fileSystem)
        let result = try move("notes.docx", contents: "doc", category: category, organizer: organizer, root: root)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.destinationURL?.path.hasSuffix("/Documents/Word/notes.docx"), true)
        XCTAssertTrue(fileSystem.fileExists(at: root.url.appendingPathComponent("Documents/Word/notes.docx")))
    }

    func testOneFailedFileDoesNotAbortTheBatch() throws {
        let root = try TemporaryDirectory()
        let category = makeCategory(name: "PDFs", extensions: ["pdf"], destination: "PDFs")
        let missing = makeSnapshot(named: "gone.pdf", in: root.url)
        let presentURL = try root.writeFile("kept.pdf", contents: "kept")
        let organizer = FileOrganizer(fileSystem: fileSystem)
        let results = organizer.organize(
            [
                FileOrganizationRequest(snapshot: missing, category: category),
                FileOrganizationRequest(snapshot: makeSnapshot(named: "kept.pdf", in: root.url), category: category),
            ],
            sourceRoot: root.url
        )
        XCTAssertEqual(results[0].status, .skipped)
        XCTAssertEqual(results[1].status, .success)
        XCTAssertFalse(fileSystem.fileExists(at: presentURL))
        XCTAssertTrue(fileSystem.fileExists(at: root.url.appendingPathComponent("PDFs/kept.pdf")))
    }

    @discardableResult
    private func move(
        _ name: String,
        contents: String,
        category: DeclutterCore.Category,
        organizer: FileOrganizer,
        root: TemporaryDirectory
    ) throws -> FileMoveResult {
        _ = try root.writeFile(name, contents: contents)
        let results = organizer.organize(
            [FileOrganizationRequest(snapshot: makeSnapshot(named: name, in: root.url), category: category)],
            sourceRoot: root.url
        )
        return try XCTUnwrap(results.first)
    }
}
