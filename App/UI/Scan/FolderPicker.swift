import AppKit
import Foundation
import UniformTypeIdentifiers

enum FolderPicker {
    @MainActor
    static func chooseDirectory(startingAt startingURL: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose the folder whose files should be classified. Nothing is moved."
        if let startingURL {
            panel.directoryURL = startingURL
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func chooseDestination(startingAt startingURL: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where files in this category should go. Nothing is moved yet."
        if let startingURL {
            panel.directoryURL = startingURL
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Test"
        panel.message = "Choose a file to test. The file is not moved."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func openJSON() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose a configuration file. Nothing changes until you confirm the summary."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func save(title: String, name: String, ext: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = ext == "json" ? [.json] : [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static var downloadsDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
}
