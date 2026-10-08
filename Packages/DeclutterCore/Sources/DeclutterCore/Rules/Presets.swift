import Foundation

public enum CategoryPreset: String, CaseIterable, Sendable, Identifiable {
    case simple
    case downloads
    case work
    case developer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .simple: "Simple"
        case .downloads: "Downloads"
        case .work: "Work"
        case .developer: "Developer"
        }
    }

    public var summary: String {
        switch self {
        case .simple:
            "Images, documents, archives, media, and a catch-all."
        case .downloads:
            "The standard folder for each kind of download."
        case .work:
            "Standard folders, plus Invoices and Screenshots above the broader rules."
        case .developer:
            "Standard folders, plus source code and config files."
        }
    }
}

public enum PresetApplyMode: String, Sendable, Equatable {
    case replace
    case merge
}

public enum CategoryPresets {
    public static func categories(for preset: CategoryPreset, now: Date = Date()) -> [Category] {
        switch preset {
        case .simple:
            renumber(simple(now: now))
        case .downloads:
            renumber(DefaultCategories.make(now: now))
        case .work:
            renumber(work(now: now))
        case .developer:
            renumber(developer(now: now))
        }
    }

    public static func apply(
        _ preset: CategoryPreset,
        to existing: [Category],
        mode: PresetApplyMode,
        now: Date = Date()
    ) -> [Category] {
        let incoming = categories(for: preset, now: now)
        switch mode {
        case .replace:
            return incoming
        case .merge:
            let names = Set(existing.map { $0.name.lowercased() })
            let additions = incoming.filter { !$0.isCatchAll && !names.contains($0.name.lowercased()) }
            let specific = existing.filter { !$0.isCatchAll }
            let catchAlls = existing.filter(\.isCatchAll)
            let mergedCatchAlls = catchAlls.isEmpty ? incoming.filter(\.isCatchAll) : catchAlls
            return renumber(specific + additions + mergedCatchAlls)
        }
    }

    private static func simple(now: Date) -> [Category] {
        [
            make(
                name: "Images",
                icon: "photo",
                destination: "Images",
                extensions: ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff", "svg"],
                now: now
            ),
            make(
                name: "Documents",
                icon: "doc",
                destination: "Documents",
                extensions: ["pdf", "doc", "docx", "txt", "md", "csv", "rtf", "pages"],
                now: now
            ),
            make(
                name: "Archives",
                icon: "archivebox",
                destination: "Archives",
                extensions: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "pkg"],
                now: now
            ),
            make(
                name: "Media",
                icon: "play.rectangle",
                destination: "Media",
                extensions: ["mp3", "wav", "m4a", "aac", "flac", "ogg", "mp4", "mov", "avi", "mkv", "webm", "m4v"],
                now: now
            ),
            catchAll(now: now),
        ]
    }

    private static func work(now: Date) -> [Category] {
        var categories = DefaultCategories.make(now: now)
        let screenshots = Category(
            name: "Screenshots",
            iconSymbol: "camera.viewfinder",
            destination: .relative("Images/Screenshots"),
            enabled: true,
            priority: 0,
            rule: .group(.and, [
                .condition(Condition(field: .extension_, op: .is, value: "png")),
                .condition(Condition(field: .filename, op: .startsWith, value: "Screenshot")),
            ]),
            createdAt: now,
            updatedAt: now
        )
        let invoices = Category(
            name: "Invoices",
            iconSymbol: "creditcard",
            destination: .relative("Finance/Invoices"),
            enabled: true,
            priority: 0,
            rule: .group(.and, [
                .condition(Condition(field: .extension_, op: .is, value: "pdf")),
                .group(.or, [
                    .condition(Condition(field: .filename, op: .contains, value: "invoice")),
                    .condition(Condition(field: .filename, op: .contains, value: "receipt")),
                ]),
            ]),
            createdAt: now,
            updatedAt: now
        )
        insert(screenshots, before: "Images", in: &categories)
        insert(invoices, before: "PDFs", in: &categories)
        return categories
    }

    private static func developer(now: Date) -> [Category] {
        let source = make(
            name: "Source Code",
            icon: "chevron.left.forwardslash.chevron.right",
            destination: "Developer/Source",
            extensions: [
                "swift", "m", "h", "c", "cc", "cpp", "hpp", "py", "js", "ts", "jsx", "tsx",
                "go", "rs", "java", "kt", "kts", "rb", "php", "sh", "cs",
            ],
            now: now
        )
        let config = make(
            name: "Config Files",
            icon: "curlybraces",
            destination: "Developer/Config",
            extensions: ["json", "xml", "yml", "yaml", "toml", "plist"],
            now: now
        )
        return [source, config] + DefaultCategories.make(now: now)
    }

    private static func make(
        name: String,
        icon: String,
        destination: String,
        extensions: [String],
        now: Date
    ) -> Category {
        Category(
            name: name,
            iconSymbol: icon,
            destination: .relative(destination),
            enabled: true,
            priority: 0,
            rule: .condition(Condition(field: .extension_, op: .isOneOf, values: extensions)),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func catchAll(now: Date) -> Category {
        Category(
            name: "Others",
            iconSymbol: "tray",
            destination: .relative("Others"),
            enabled: true,
            priority: 0,
            rule: .group(.and, []),
            isCatchAll: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func insert(_ category: Category, before name: String, in categories: inout [Category]) {
        if let index = categories.firstIndex(where: { $0.name == name }) {
            categories.insert(category, at: index)
        } else {
            categories.insert(category, at: 0)
        }
    }

    private static func renumber(_ categories: [Category]) -> [Category] {
        let specific = categories.filter { !$0.isCatchAll }
        let catchAlls = categories.filter(\.isCatchAll)
        return (specific + catchAlls).enumerated().map { index, category in
            var copy = category
            copy.priority = index
            return copy
        }
    }
}
