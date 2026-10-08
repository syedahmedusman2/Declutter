import Foundation

public struct FileEventFlag: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let created = FileEventFlag(rawValue: 1 << 0)
    public static let removed = FileEventFlag(rawValue: 1 << 1)
    public static let renamed = FileEventFlag(rawValue: 1 << 2)
    public static let modified = FileEventFlag(rawValue: 1 << 3)
    public static let isDirectory = FileEventFlag(rawValue: 1 << 4)
}

public struct FileEvent: Sendable, Equatable {
    public var path: String
    public var eventID: UInt64
    public var flags: FileEventFlag

    public init(path: String, eventID: UInt64, flags: FileEventFlag = .created) {
        self.path = path
        self.eventID = eventID
        self.flags = flags
    }
}

public protocol FileEventSource: Sendable {
    func events(for root: URL, since eventID: UInt64?) -> AsyncStream<FileEvent>
}
