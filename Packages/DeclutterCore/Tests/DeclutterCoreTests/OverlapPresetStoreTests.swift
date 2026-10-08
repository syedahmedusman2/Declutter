import XCTest
@testable import DeclutterCore

final class OverlapPresetStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testWorkPresetOverlapAndSampleFile() throws {
        let categories = CategoryPresets.categories(for: .work, now: now)
        let warnings = OverlapDetector().detect(categories: categories)
        let pdfs = try XCTUnwrap(warnings.first { $0.categoryName == "PDFs" && $0.otherCategoryName == "Invoices" })
        XCTAssertEqual(pdfs.kind, .overlaps)
        XCTAssertTrue(pdfs.message.contains("Overlaps with Invoices"))

        let images = try XCTUnwrap(warnings.first { $0.categoryName == "Images" && $0.otherCategoryName == "Screenshots" })
        XCTAssertEqual(images.kind, .overlaps)

        let sample = OverlapDetector().check(
            file: makeSnapshot(named: "invoice-2026.pdf"),
            categories: categories
        )
        XCTAssertEqual(sample.winnerName, "Invoices")
        XCTAssertEqual(sample.matches.map(\.name), ["Invoices", "PDFs"])
        XCTAssertTrue(sample.summary.contains("Invoices wins"))
    }

    func testBroaderRuleShadowsTheLowerOne() throws {
        let broad = makeCategory(name: "PDFs", extensions: ["pdf"], priority: 0)
        let narrow = Category(
            name: "Invoices",
            iconSymbol: "creditcard",
            destination: .relative("Finance/Invoices"),
            enabled: true,
            priority: 1,
            rule: .group(.and, [
                .condition(Condition(field: .extension_, op: .isOneOf, values: ["pdf"])),
                .condition(Condition(field: .filename, op: .contains, value: "invoice")),
            ]),
            createdAt: now,
            updatedAt: now
        )
        let warnings = OverlapDetector().detect(categories: [broad, narrow])
        let shadowed = try XCTUnwrap(warnings.first { $0.categoryName == "Invoices" })
        XCTAssertEqual(shadowed.kind, .shadowed)
        XCTAssertTrue(shadowed.message.contains("Partially shadowed by PDFs"))

        var disabled = broad
        disabled.enabled = false
        XCTAssertTrue(OverlapDetector().detect(categories: [disabled, narrow]).isEmpty)
    }

    func testPresetsAndMerge() {
        let simple = CategoryPresets.categories(for: .simple, now: now)
        XCTAssertEqual(simple.map(\.name), ["Images", "Documents", "Archives", "Media", "Others"])
        XCTAssertEqual(simple.map(\.priority), Array(0..<simple.count))
        XCTAssertTrue(simple.last?.isCatchAll == true)

        let downloads = CategoryPresets.categories(for: .downloads, now: now)
        XCTAssertEqual(downloads.map(\.name), DefaultCategories.make(now: now).map(\.name))

        let work = CategoryPresets.categories(for: .work, now: now)
        XCTAssertLessThan(priority(of: "Screenshots", in: work), priority(of: "Images", in: work))
        XCTAssertLessThan(priority(of: "Invoices", in: work), priority(of: "PDFs", in: work))
        XCTAssertEqual(work.first { $0.name == "Invoices" }?.destination.path, "Finance/Invoices")

        let developer = CategoryPresets.categories(for: .developer, now: now)
        XCTAssertEqual(developer.first?.name, "Source Code")
        XCTAssertEqual(developer.dropFirst().first?.name, "Config Files")
        XCTAssertEqual(developer.last?.name, "Others")

        let custom = makeCategory(name: "Invoices", extensions: ["pdf"], priority: 0)
        let merged = CategoryPresets.apply(.work, to: [custom], mode: .merge, now: now)
        XCTAssertEqual(merged.filter { $0.name == "Invoices" }.count, 1)
        XCTAssertEqual(merged.first { $0.name == "Invoices" }?.id, custom.id)
        XCTAssertNotNil(merged.first { $0.name == "Screenshots" })
        XCTAssertEqual(merged.last?.name, "Others")

        let replaced = CategoryPresets.apply(.simple, to: [custom], mode: .replace, now: now)
        XCTAssertEqual(replaced.map(\.name), simple.map(\.name))
    }

    func testCategoryStoreRoundTripBackupAndSchema() throws {
        let directory = try TemporaryDirectory()
        let store = CategoryStore(fileURL: directory.url.appendingPathComponent("config.json"))
        XCTAssertNil(try store.load())

        let first = [makeCategory(name: "PDFs", extensions: ["pdf"], priority: 0)]
        try store.save(first)
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertFalse(loaded.isReadOnly)
        XCTAssertEqual(loaded.categories.map(\.name), ["PDFs"])

        let second = [makeCategory(name: "Images", extensions: ["jpg"], priority: 0)]
        try store.save(second, loadedSchemaVersion: SchemaVersion.current)
        let backup = try JSONDecoder().decode(CategoryDocument.self, from: Data(contentsOf: store.backupURL))
        XCTAssertEqual(backup.categories.map(\.name), ["PDFs"])
        XCTAssertEqual(backup.schemaVersion, SchemaVersion.current)
        let current = try XCTUnwrap(try store.load())
        XCTAssertEqual(current.categories.map(\.name), ["Images"])

        let newer = CategoryDocument(schemaVersion: SchemaVersion.current + 10, categories: first)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(newer).write(to: store.fileURL)
        let readOnly = try XCTUnwrap(try store.load())
        XCTAssertTrue(readOnly.isReadOnly)
        XCTAssertEqual(readOnly.categories.map(\.name), ["PDFs"])
        XCTAssertNotNil(readOnly.message)
        XCTAssertThrowsError(try store.save(second, loadedSchemaVersion: SchemaVersion.current + 10)) { error in
            XCTAssertEqual(error as? CategoryStoreError, .readOnly)
        }

        var legacy = CategoryDocument(schemaVersion: 1, categories: first)
        if SchemaVersion.current == 1 {
            legacy.schemaVersion = 1
        }
        let migrated = try CategoryMigrator.migrate(legacy, upTo: 2)
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.categories.map(\.name), ["PDFs"])
    }

    private func priority(of name: String, in categories: [DeclutterCore.Category]) -> Int {
        categories.first { $0.name == name }?.priority ?? -1
    }
}
