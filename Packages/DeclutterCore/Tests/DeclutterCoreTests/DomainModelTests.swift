import XCTest
@testable import DeclutterCore

final class DomainModelTests: XCTestCase {
    func testModelsRoundTripWithSchemaVersion() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let condition = Condition(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            field: .extension_,
            op: .isOneOf,
            values: ["pdf", "PDF"],
            matchCase: false
        )
        let category = Category(
            id: UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "PDFs",
            iconSymbol: "doc.richtext",
            destination: .relative("Documents/PDFs"),
            enabled: true,
            priority: 10,
            rule: .group(.and, [.condition(condition), .group(.or, [.condition(condition)])]),
            conflictPolicy: .autoRename,
            action: .move,
            isCatchAll: false,
            createdAt: now,
            updatedAt: now
        )
        let folder = SourceFolder(
            id: UUID(uuidString: "CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            displayName: "Downloads",
            bookmarkData: Data([1, 2, 3]),
            ruleSetID: UUID(uuidString: "DDDDDDDD-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            mode: .existingAndNew,
            isActive: true
        )
        let snapshot = makeSnapshot(named: "archive.tar.gz")

        XCTAssertEqual(try roundTrip(category), category)
        XCTAssertEqual(try roundTrip(folder), folder)
        XCTAssertEqual(try roundTrip(snapshot), snapshot)
        XCTAssertEqual(category.schemaVersion, SchemaVersion.current)
        XCTAssertEqual(folder.schemaVersion, SchemaVersion.current)
        XCTAssertEqual(snapshot.schemaVersion, SchemaVersion.current)
        XCTAssertEqual(condition.schemaVersion, SchemaVersion.current)

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(category)) as! [String: Any]
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let destination = json["destination"] as! [String: Any]
        XCTAssertEqual(destination["type"] as? String, "relative")
        XCTAssertEqual(destination["path"] as? String, "Documents/PDFs")
    }

    func testDefaultCategoriesMatchAppendixA() throws {
        let categories = DefaultCategories.make()
        XCTAssertEqual(
            categories.map(\.name),
            [
                "Images", "PDFs", "Word Documents", "Text Files", "Apple Documents", "Rich Text",
                "Spreadsheets", "Presentations", "Archives", "Installers", "Audio", "Video",
                "Applications", "Others",
            ]
        )
        XCTAssertEqual(categories.map(\.priority), Array(0..<categories.count))
        XCTAssertEqual(Set(categories.map(\.id)).count, categories.count)
        XCTAssertTrue(categories.allSatisfy(\.enabled))
        XCTAssertTrue(categories.allSatisfy { $0.action == .move })
        XCTAssertEqual(categories.filter(\.isCatchAll).map(\.name), ["Others"])

        let expectedDestinations = [
            "Images": "Images",
            "PDFs": "PDFs",
            "Word Documents": "Documents/Word",
            "Text Files": "Documents/Text",
            "Apple Documents": "Documents/Apple",
            "Rich Text": "Documents/Rich Text",
            "Spreadsheets": "Spreadsheets",
            "Presentations": "Presentations",
            "Archives": "Archives",
            "Installers": "Installers",
            "Audio": "Audio",
            "Video": "Video",
            "Applications": "Applications",
            "Others": "Others",
        ]
        let expectedExtensions = [
            "Images": ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff", "svg"],
            "PDFs": ["pdf"],
            "Word Documents": ["doc", "docx"],
            "Text Files": ["txt", "md", "csv", "log"],
            "Apple Documents": ["pages", "numbers", "key"],
            "Rich Text": ["rtf"],
            "Spreadsheets": ["xls", "xlsx", "ods"],
            "Presentations": ["ppt", "pptx", "odp"],
            "Archives": ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"],
            "Installers": ["dmg", "pkg"],
            "Audio": ["mp3", "wav", "m4a", "aac", "flac", "ogg"],
            "Video": ["mp4", "mov", "avi", "mkv", "webm", "m4v"],
            "Applications": ["app"],
        ]
        for category in categories {
            guard case .relative(let path) = category.destination else {
                XCTFail("\(category.name) should use a relative destination")
                continue
            }
            XCTAssertEqual(path, expectedDestinations[category.name])
            if category.isCatchAll {
                guard case .group(.and, let children) = category.rule else {
                    XCTFail("Catch-all should not pretend to have an extension list")
                    continue
                }
                XCTAssertTrue(children.isEmpty)
            } else {
                guard case .condition(let condition) = category.rule else {
                    XCTFail("\(category.name) should be an extension condition")
                    continue
                }
                XCTAssertEqual(condition.field, .extension_)
                XCTAssertEqual(condition.op, .isOneOf)
                XCTAssertFalse(condition.matchCase)
                XCTAssertEqual(condition.values, expectedExtensions[category.name])
            }
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
