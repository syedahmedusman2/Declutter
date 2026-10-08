import XCTest
@testable import DownloadOrganizerCore

final class ClassificationEngineTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/Downloads", isDirectory: true)

    func testExtensionMatchingIsCaseInsensitive() {
        let engine = ClassificationEngine(categories: DefaultCategories.make())
        for name in ["report.PDF", "report.pdf", "report.Pdf"] {
            let classification = engine.classify(makeSnapshot(named: name), sourceRoot: source)
            XCTAssertEqual(classification?.category.name, "PDFs", name)
            XCTAssertEqual(classification?.explanation.conditions.first?.passed, true, name)
        }
        for name in ["photo.JPG", "photo.jpg", "photo.Jpeg", "photo.jpeg"] {
            XCTAssertEqual(
                engine.classify(makeSnapshot(named: name), sourceRoot: source)?.category.name,
                "Images",
                name
            )
        }
    }

    func testNoExtensionUsesCatchAll() {
        let engine = ClassificationEngine(categories: DefaultCategories.make())
        let classification = engine.classify(makeSnapshot(named: "README"), sourceRoot: source)
        XCTAssertEqual(classification?.category.name, "Others")
        XCTAssertEqual(classification?.explanation.ruleSummary, "Catch-all")
        XCTAssertEqual(
            classification?.explanation.destinationURL.path,
            "/Downloads/Others/README"
        )
    }

    func testMultipleDotsUseTheLastExtension() {
        let engine = ClassificationEngine(categories: DefaultCategories.make())
        let archive = engine.classify(makeSnapshot(named: "archive.tar.gz"), sourceRoot: source)
        XCTAssertEqual(archive?.category.name, "Archives")
        XCTAssertEqual(makeSnapshot(named: "archive.tar.gz").ext, "gz")
        XCTAssertEqual(makeSnapshot(named: "archive.tar.gz").nameWithoutExt, "archive.tar")

        let pdf = engine.classify(makeSnapshot(named: "my.file.pdf"), sourceRoot: source)
        XCTAssertEqual(pdf?.category.name, "PDFs")

        let backup = engine.classify(makeSnapshot(named: "notes.pdf.bak"), sourceRoot: source)
        XCTAssertEqual(backup?.category.name, "Others")
    }

    func testDisabledCatchAllLeavesFileUnmatched() {
        var categories = DefaultCategories.make()
        categories[categories.count - 1].enabled = false
        let engine = ClassificationEngine(categories: categories)
        XCTAssertNil(engine.classify(makeSnapshot(named: "README"), sourceRoot: source))
        XCTAssertEqual(engine.classify(makeSnapshot(named: "a.pdf"), sourceRoot: source)?.category.name, "PDFs")
    }

    func testHigherPriorityExtensionWins() {
        let invoices = makeCategory(name: "Invoices", extensions: ["pdf"], destination: "Finance", priority: -1)
        let engine = ClassificationEngine(categories: [invoices] + DefaultCategories.make())
        let classification = engine.classify(makeSnapshot(named: "invoice.pdf"), sourceRoot: source)
        XCTAssertEqual(classification?.category.name, "Invoices")
    }

    func testMatchCaseCanRequireExactExtension() {
        let category = makeCategory(name: "Exact PDF", extensions: [], priority: 0, matchCase: true, op: .is, value: "PDF")
        let engine = ClassificationEngine(categories: [category])
        XCTAssertEqual(engine.classify(makeSnapshot(named: "a.PDF"), sourceRoot: source)?.category.name, "Exact PDF")
        XCTAssertNil(engine.classify(makeSnapshot(named: "a.pdf"), sourceRoot: source))
    }

    func testFilenameContainsMatches() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let category = Category(
            name: "Invoices",
            iconSymbol: "folder",
            destination: .relative("Finance"),
            enabled: true,
            priority: 0,
            rule: .condition(Condition(field: .filename, op: .contains, value: "invoice")),
            createdAt: now,
            updatedAt: now
        )
        let engine = ClassificationEngine(categories: [category])
        let match = engine.classify(makeSnapshot(named: "invoice.pdf"), sourceRoot: source)
        XCTAssertEqual(match?.category.name, "Invoices")
        XCTAssertEqual(match?.explanation.conditions.first?.actualValue, "invoice")
        XCTAssertNil(engine.classify(makeSnapshot(named: "notes.pdf"), sourceRoot: source))
    }

    func testInvoicesAbovePDFsAndExplanation() {
        let categories = CategoryPresets.categories(for: .work, now: Date(timeIntervalSince1970: 0))
        let engine = ClassificationEngine(categories: categories)
        let invoice = engine.classify(makeSnapshot(named: "invoice-2026.pdf"), sourceRoot: source)
        XCTAssertEqual(invoice?.category.name, "Invoices")
        XCTAssertEqual(invoice?.explanation.destinationURL.path, "/Downloads/Finance/Invoices/invoice-2026.pdf")
        let results = invoice?.explanation.conditions ?? []
        XCTAssertTrue(results.contains { $0.description == "Extension is pdf" && $0.passed && $0.actualValue == "pdf" })
        XCTAssertTrue(results.contains { $0.description == "Filename contains invoice" && $0.passed && $0.actualValue == "invoice-2026" })
        XCTAssertTrue(results.contains { $0.description == "Filename contains receipt" && !$0.passed && $0.actualValue == "invoice-2026" })

        XCTAssertEqual(engine.classify(makeSnapshot(named: "report.pdf"), sourceRoot: source)?.category.name, "PDFs")
        XCTAssertEqual(
            engine.classify(makeSnapshot(named: "Screenshot 1.png"), sourceRoot: source)?.category.name,
            "Screenshots"
        )
        XCTAssertEqual(engine.classify(makeSnapshot(named: "photo.png"), sourceRoot: source)?.category.name, "Images")
    }

    func testCustomCategoryFromEditorComposerWinsAndPersists() throws {
        let advanced = RuleNode.group(.or, [
            .condition(Condition(field: .filename, op: .contains, value: "invoice")),
            .condition(Condition(field: .filename, op: .contains, value: "receipt")),
        ])
        let rule = RuleComposer.compose(extensions: ["pdf"], advanced: advanced, catchAll: false)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var invoices = Category(
            name: "Invoices",
            iconSymbol: "creditcard",
            destination: .relative("Finance/Invoices"),
            enabled: true,
            priority: 0,
            rule: rule,
            createdAt: now,
            updatedAt: now
        )
        let defaults = DefaultCategories.make(now: now)
        let pdfIndex = defaults.firstIndex { $0.name == "PDFs" } ?? 1
        var categories = defaults
        categories.insert(invoices, at: pdfIndex)
        categories = categories.enumerated().map { index, category in
            var copy = category
            copy.priority = index
            return copy
        }
        invoices = categories.first { $0.name == "Invoices" }!

        let engine = ClassificationEngine(categories: categories)
        XCTAssertEqual(
            engine.classify(makeSnapshot(named: "invoice-2026.pdf"), sourceRoot: source)?.category.name,
            "Invoices"
        )
        XCTAssertEqual(
            engine.classify(makeSnapshot(named: "report.pdf"), sourceRoot: source)?.category.name,
            "PDFs"
        )

        let directory = try TemporaryDirectory()
        let store = CategoryStore(fileURL: directory.url.appendingPathComponent("config.json"))
        try store.save(categories)
        let loaded = try store.load()
        XCTAssertEqual(loaded?.categories.first { $0.name == "Invoices" }?.rule, rule)
        XCTAssertEqual(loaded?.categories.first { $0.name == "Invoices" }?.destination.path, "Finance/Invoices")
        if case .group(.and, let children) = RuleComposer.compose(extensions: [], advanced: nil, catchAll: false) {
            XCTAssertTrue(children.isEmpty, "Editor must not treat an empty non-catch-all as ready to save.")
        } else {
            XCTFail("Expected empty AND for a category with no extensions or conditions")
        }
    }

    func testCustomExtensionAndCase() {
        let sketch = makeCategory(name: "Sketches", extensions: ["sketch"], destination: "Design", priority: 0)
        let engine = ClassificationEngine(categories: [sketch] + DefaultCategories.make())
        XCTAssertEqual(engine.classify(makeSnapshot(named: "logo.SKETCH"), sourceRoot: source)?.category.name, "Sketches")
        XCTAssertEqual(engine.classify(makeSnapshot(named: "logo.jpg"), sourceRoot: source)?.category.name, "Images")

        let exact = makeCategory(name: "Exact", extensions: [], priority: 0, matchCase: true, op: .equals, value: "Invoice")
        var exactRule = exact
        exactRule.rule = .condition(Condition(field: .filename, op: .equals, value: "Invoice", matchCase: true))
        let caseEngine = ClassificationEngine(categories: [exactRule])
        XCTAssertNotNil(caseEngine.classify(makeSnapshot(named: "Invoice.pdf"), sourceRoot: source))
        XCTAssertNil(caseEngine.classify(makeSnapshot(named: "invoice.pdf"), sourceRoot: source))
    }

    func testUTTypeConformance() {
        let images = Category(
            name: "Pictures",
            iconSymbol: "photo",
            destination: .relative("Pictures"),
            enabled: true,
            priority: 0,
            rule: .condition(Condition(field: .fileType, op: .conformsTo, value: "public.image")),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let engine = ClassificationEngine(categories: [images])
        let fromExtension = engine.classify(makeSnapshot(named: "photo.jpg"), sourceRoot: source)
        XCTAssertEqual(fromExtension?.category.name, "Pictures")
        XCTAssertEqual(fromExtension?.explanation.conditions.first?.passed, true)
        XCTAssertNil(engine.classify(makeSnapshot(named: "notes.txt"), sourceRoot: source))

        let typed = engine.classify(
            makeSnapshot(named: "photo.bin", utType: "public.jpeg"),
            sourceRoot: source
        )
        XCTAssertEqual(typed?.category.name, "Pictures")
    }

    func testRuleReportsHigherPriorityWinner() throws {
        let categories = CategoryPresets.categories(for: .work, now: Date(timeIntervalSince1970: 0))
        let engine = ClassificationEngine(categories: categories)
        let pdfs = try XCTUnwrap(categories.first { $0.name == "PDFs" })
        let report = engine.testRule(pdfs, file: makeSnapshot(named: "invoice-2026.pdf"), sourceRoot: source)
        XCTAssertTrue(report.matched)
        XCTAssertFalse(report.applies)
        XCTAssertEqual(report.higherPriorityWinnerName, "Invoices")
        XCTAssertTrue(report.explanation.conditions.contains { $0.passed })
        XCTAssertEqual(report.explanation.destinationURL.lastPathComponent, "invoice-2026.pdf")

        let plain = engine.testRule(pdfs, file: makeSnapshot(named: "report.pdf"), sourceRoot: source)
        XCTAssertTrue(plain.applies)
        XCTAssertNil(plain.higherPriorityWinnerName)
    }
}
