import XCTest
@testable import DeclutterCore

final class RuleEngineTests: XCTestCase {
    private let engine = RuleEngine()
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    func testEveryOperator() {
        let file = makeSnapshot(
            named: "Invoice-2026.pdf",
            utType: "com.adobe.pdf",
            size: 150,
            created: moment,
            modified: moment
        )
        let earlier = RuleValueParsing.format(date: moment.addingTimeInterval(-3_600))
        let later = RuleValueParsing.format(date: moment.addingTimeInterval(3_600))
        let exact = RuleValueParsing.format(date: moment)

        let cases: [(Condition, Bool)] = [
            (Condition(field: .extension_, op: .is, value: "pdf"), true),
            (Condition(field: .extension_, op: .is, value: "png"), false),
            (Condition(field: .extension_, op: .isNot, value: "png"), true),
            (Condition(field: .extension_, op: .isNot, value: "pdf"), false),
            (Condition(field: .extension_, op: .isOneOf, values: ["png", "pdf"]), true),
            (Condition(field: .extension_, op: .isOneOf, values: ["png", "jpg"]), false),
            (Condition(field: .filename, op: .contains, value: "invoice"), true),
            (Condition(field: .filename, op: .contains, value: "receipt"), false),
            (Condition(field: .filename, op: .notContains, value: "receipt"), true),
            (Condition(field: .filename, op: .notContains, value: "invoice"), false),
            (Condition(field: .filename, op: .startsWith, value: "invoice"), true),
            (Condition(field: .filename, op: .startsWith, value: "2026"), false),
            (Condition(field: .filename, op: .endsWith, value: "2026"), true),
            (Condition(field: .filename, op: .endsWith, value: "invoice"), false),
            (Condition(field: .filename, op: .equals, value: "invoice-2026"), true),
            (Condition(field: .filename, op: .equals, value: "invoice"), false),
            (Condition(field: .filename, op: .notEquals, value: "other"), true),
            (Condition(field: .filename, op: .notEquals, value: "invoice-2026"), false),
            (Condition(field: .filename, op: .regex, value: #"invoice-\d+"#), true),
            (Condition(field: .filename, op: .regex, value: #"^receipt"#), false),
            (Condition(field: .fileType, op: .is, value: "com.adobe.pdf"), true),
            (Condition(field: .fileType, op: .is, value: "public.jpeg"), false),
            (Condition(field: .fileType, op: .conformsTo, value: "public.data"), true),
            (Condition(field: .fileType, op: .conformsTo, value: "public.image"), false),
            (Condition(field: .size, op: .greaterThan, value: "100"), true),
            (Condition(field: .size, op: .greaterThan, value: "150"), false),
            (Condition(field: .size, op: .lessThan, value: "200"), true),
            (Condition(field: .size, op: .lessThan, value: "150"), false),
            (Condition(field: .size, op: .equals, value: "150"), true),
            (Condition(field: .size, op: .equals, value: "151"), false),
            (Condition(field: .size, op: .between, values: ["100", "200"]), true),
            (Condition(field: .size, op: .between, values: ["1", "10"]), false),
            (Condition(field: .createdDate, op: .after, value: earlier), true),
            (Condition(field: .createdDate, op: .after, value: later), false),
            (Condition(field: .createdDate, op: .before, value: later), true),
            (Condition(field: .createdDate, op: .before, value: earlier), false),
            (Condition(field: .createdDate, op: .between, values: [earlier, later]), true),
            (Condition(field: .createdDate, op: .between, values: [later, later]), false),
            (Condition(field: .modifiedDate, op: .before, value: later), true),
            (Condition(field: .modifiedDate, op: .after, value: earlier), true),
            (Condition(field: .modifiedDate, op: .between, values: [earlier, exact]), true),
            (Condition(field: .modifiedDate, op: .before, value: earlier), false),
        ]

        for (condition, expected) in cases {
            let result = engine.evaluate(.condition(condition), file: file)
            XCTAssertEqual(result.passed, expected, result.description)
            XCTAssertEqual(result.kind, .condition)
            XCTAssertFalse(result.actualValue.isEmpty, result.description)
            XCTAssertTrue(result.warnings.isEmpty, result.description)
        }
    }

    func testNestedGroupsNotAndInvalidRegex() {
        let rule = RuleNode.group(.and, [
            .group(.or, [
                .condition(Condition(field: .filename, op: .contains, value: "invoice")),
                .condition(Condition(field: .filename, op: .contains, value: "receipt")),
            ]),
            .group(.not, [
                .condition(Condition(field: .filename, op: .contains, value: "draft")),
            ]),
        ])

        let invoice = engine.evaluate(rule, file: makeSnapshot(named: "invoice-final.pdf"))
        XCTAssertTrue(invoice.passed)
        XCTAssertEqual(invoice.conditionResults.map(\.passed), [true, false, false])

        let draft = engine.evaluate(rule, file: makeSnapshot(named: "invoice-draft.pdf"))
        XCTAssertFalse(draft.passed)
        XCTAssertEqual(draft.conditionResults.map(\.passed), [true, false, true])

        let neither = engine.evaluate(rule, file: makeSnapshot(named: "notes.pdf"))
        XCTAssertFalse(neither.passed)

        let nor = RuleNode.group(.not, [
            .condition(Condition(field: .filename, op: .contains, value: "a")),
            .condition(Condition(field: .filename, op: .contains, value: "b")),
        ])
        XCTAssertFalse(engine.evaluate(nor, file: makeSnapshot(named: "a-file.txt")).passed)
        XCTAssertTrue(engine.evaluate(nor, file: makeSnapshot(named: "zzz.txt")).passed)

        XCTAssertTrue(engine.evaluate(.group(.and, []), file: makeSnapshot(named: "a")).passed)
        XCTAssertFalse(engine.evaluate(.group(.or, []), file: makeSnapshot(named: "a")).passed)

        let broken = Condition(field: .filename, op: .regex, value: "(unclosed")
        let invalid = engine.evaluate(.condition(broken), file: makeSnapshot(named: "invoice.pdf"))
        XCTAssertFalse(invalid.passed)
        XCTAssertEqual(invalid.warning, "Invalid regular expression")
        XCTAssertEqual(invalid.actualValue, "invoice")
        XCTAssertEqual(RuleValidator.issues(in: .condition(broken)).count, 1)
        XCTAssertNil(RuleValidator.regexError(pattern: #"invoice-\d+"#))
    }

    func testCaseMatchingAndExplanationValues() {
        let sensitive = Condition(field: .filename, op: .equals, value: "Invoice", matchCase: true)
        XCTAssertTrue(engine.evaluate(.condition(sensitive), file: makeSnapshot(named: "Invoice.pdf")).passed)
        XCTAssertFalse(engine.evaluate(.condition(sensitive), file: makeSnapshot(named: "invoice.pdf")).passed)

        let insensitive = Condition(field: .extension_, op: .is, value: "PDF", matchCase: false)
        let result = engine.evaluate(.condition(insensitive), file: makeSnapshot(named: "a.pdf"))
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.actualValue, "pdf")
        XCTAssertEqual(result.description, "Extension is PDF")

        let exactExtension = Condition(field: .extension_, op: .is, value: "PDF", matchCase: true)
        XCTAssertFalse(engine.evaluate(.condition(exactExtension), file: makeSnapshot(named: "a.pdf")).passed)
        XCTAssertTrue(engine.evaluate(.condition(exactExtension), file: makeSnapshot(named: "a.PDF")).passed)
    }

    func testSizeBetweenIsInclusiveAndDatesRejectMissingValues() {
        let between = Condition(field: .size, op: .between, values: ["200", "100"])
        XCTAssertTrue(engine.evaluate(.condition(between), file: makeSnapshot(named: "a.bin", size: 100)).passed)
        XCTAssertTrue(engine.evaluate(.condition(between), file: makeSnapshot(named: "a.bin", size: 200)).passed)
        XCTAssertFalse(engine.evaluate(.condition(between), file: makeSnapshot(named: "a.bin", size: 201)).passed)

        let created = Condition(field: .createdDate, op: .before, value: RuleValueParsing.format(date: moment))
        let missing = engine.evaluate(.condition(created), file: makeSnapshot(named: "a.txt"))
        XCTAssertFalse(missing.passed)
        XCTAssertEqual(missing.actualValue, "(none)")
    }

    func testExtensionChipsRoundTrip() {
        let advanced = RuleNode.group(.or, [
            .condition(Condition(field: .filename, op: .contains, value: "invoice")),
            .condition(Condition(field: .filename, op: .contains, value: "receipt")),
        ])
        let composed = RuleComposer.compose(extensions: ["pdf", ".PDF"], advanced: advanced, catchAll: false)
        XCTAssertEqual(RuleComposer.primaryExtensions(in: composed), ["pdf", "PDF"])
        XCTAssertEqual(RuleComposer.advancedRule(in: composed), advanced)

        let extensionsOnly = RuleComposer.compose(extensions: ["sketch"], advanced: nil, catchAll: false)
        XCTAssertEqual(RuleComposer.primaryExtensions(in: extensionsOnly), ["sketch"])
        XCTAssertNil(RuleComposer.advancedRule(in: extensionsOnly))
        XCTAssertTrue(engine.evaluate(extensionsOnly, file: makeSnapshot(named: "logo.sketch")).passed)
    }
}
