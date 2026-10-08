import Foundation

public enum AutomationMode: String, Codable, Sendable, Equatable {
    case existingOnly
    case newOnly
    case existingAndNew
}

public struct SourceFolder: Identifiable, Codable, Sendable, Equatable {
    public var schemaVersion: Int = SchemaVersion.current
    public var id: UUID
    public var displayName: String
    public var bookmarkData: Data?
    public var ruleSetID: UUID
    public var mode: AutomationMode
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkData: Data? = nil,
        ruleSetID: UUID = UUID(),
        mode: AutomationMode,
        isActive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.ruleSetID = ruleSetID
        self.mode = mode
        self.isActive = isActive
    }
}
