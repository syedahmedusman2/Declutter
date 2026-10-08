import Foundation

public enum DefaultCategories {
    public static func make(now: Date = Date()) -> [Category] {
        let specs: [(name: String, icon: String, destination: String, extensions: [String], catchAll: Bool)] = [
            ("Images", "photo", "Images", ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff", "svg"], false),
            ("PDFs", "doc.richtext", "PDFs", ["pdf"], false),
            ("Word Documents", "doc.text", "Documents/Word", ["doc", "docx"], false),
            ("Text Files", "doc.plaintext", "Documents/Text", ["txt", "md", "csv", "log"], false),
            ("Apple Documents", "apple.logo", "Documents/Apple", ["pages", "numbers", "key"], false),
            ("Rich Text", "text.quote", "Documents/Rich Text", ["rtf"], false),
            ("Spreadsheets", "tablecells", "Spreadsheets", ["xls", "xlsx", "ods"], false),
            ("Presentations", "rectangle.on.rectangle.angled", "Presentations", ["ppt", "pptx", "odp"], false),
            ("Archives", "archivebox", "Archives", ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"], false),
            ("Installers", "shippingbox", "Installers", ["dmg", "pkg"], false),
            ("Audio", "waveform", "Audio", ["mp3", "wav", "m4a", "aac", "flac", "ogg"], false),
            ("Video", "film", "Video", ["mp4", "mov", "avi", "mkv", "webm", "m4v"], false),
            ("Applications", "app.badge", "Applications", ["app"], false),
            ("Others", "tray", "Others", [], true),
        ]

        return specs.enumerated().map { index, spec in
            let rule: RuleNode
            if spec.catchAll {
                rule = .group(.and, [])
            } else {
                rule = .condition(
                    Condition(field: .extension_, op: .isOneOf, values: spec.extensions, matchCase: false)
                )
            }
            return Category(
                name: spec.name,
                iconSymbol: spec.icon,
                destination: .relative(spec.destination),
                enabled: true,
                priority: index,
                rule: rule,
                conflictPolicy: nil,
                action: .move,
                isCatchAll: spec.catchAll,
                createdAt: now,
                updatedAt: now
            )
        }
    }
}
