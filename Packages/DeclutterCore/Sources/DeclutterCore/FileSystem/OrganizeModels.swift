import Foundation

public enum OrganizeMessage {
    public static let disappeared = "disappeared"
    public static let changed = "File changed before it could be moved"
    public static let noCategory = "No category"
    public static let link = "Links are not moved"
    public static let folder = "Folders are not moved"
    public static let hidden = "Hidden files are not moved"
    public static let systemFile = "System files are not moved"
    public static let temporary = "Partial downloads are not moved"
    public static let categoryFolder = "Source is a category folder"
    public static let insideCategory = "File is inside a category folder"
    public static let alreadyThere = "File is already in the destination folder"
    public static let sameDirectory = "Destination is the source folder"
    public static let loop = "Destination is inside the source"
    public static let outsideSource = "Destination is outside the source folder"
    public static let outsideScope = "Destination is outside the granted folders"
    public static let nameExists = "A file with this name already exists"
    public static let needsDecision = "Choose what to do with the existing file"
    public static let replaceNeedsConfirmation = "Replace needs confirmation"
    public static let moved = "Moved"
    public static let replaced = "Replaced the existing file, which is in the Trash"
    public static let cancelled = "Cancelled"
    public static let tooManyNames = "Too many files already use this name"
    public static let journalFailed = "Could not record the move"

    public static func batchLimit(_ limit: Int) -> String {
        "Batch is larger than the maximum of \(limit) files"
    }
}

public enum PlannedAction: String, Codable, Sendable, Equatable {
    case move
    case skip
    case replace
    case needsDecision
    case blocked
}

public enum ConflictStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case autoRename
    case skip
    case replace
    case needsDecision
    case blocked
}

public struct OrganizeOptions: Sendable, Equatable {
    public var globalConflictPolicy: ConflictPolicy
    public var permittedRoots: [URL]
    public var maximumBatchSize: Int
    public var bulkConfirmationThreshold: Int
    public var workerCount: Int
    public var moveSymlinks: Bool

    public init(
        globalConflictPolicy: ConflictPolicy = .autoRename,
        permittedRoots: [URL] = [],
        maximumBatchSize: Int = 10_000,
        bulkConfirmationThreshold: Int = 50,
        workerCount: Int = 4,
        moveSymlinks: Bool = false
    ) {
        self.globalConflictPolicy = globalConflictPolicy
        self.permittedRoots = permittedRoots
        self.maximumBatchSize = max(maximumBatchSize, 1)
        self.bulkConfirmationThreshold = max(bulkConfirmationThreshold, 1)
        self.workerCount = max(workerCount, 1)
        self.moveSymlinks = moveSymlinks
    }
}

public struct PlannedMove: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var snapshot: FileSnapshot
    public var categoryID: UUID?
    public var categoryName: String
    public var ruleSummary: String
    public var destinationDirectory: URL
    public var proposedURL: URL
    public var action: PlannedAction
    public var conflict: ConflictStatus
    public var policy: ConflictPolicy
    public var predictedStatus: OperationStatus
    public var message: String

    public init(
        id: UUID = UUID(),
        snapshot: FileSnapshot,
        categoryID: UUID?,
        categoryName: String,
        ruleSummary: String,
        destinationDirectory: URL,
        proposedURL: URL,
        action: PlannedAction,
        conflict: ConflictStatus,
        policy: ConflictPolicy,
        predictedStatus: OperationStatus,
        message: String
    ) {
        self.id = id
        self.snapshot = snapshot
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.ruleSummary = ruleSummary
        self.destinationDirectory = destinationDirectory
        self.proposedURL = proposedURL
        self.action = action
        self.conflict = conflict
        self.policy = policy
        self.predictedStatus = predictedStatus
        self.message = message
    }
}

public struct OrganizeProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
    public var fileName: String

    public init(completed: Int, total: Int, fileName: String) {
        self.completed = completed
        self.total = total
        self.fileName = fileName
    }
}

public struct BatchResult: Sendable, Equatable {
    public var batchID: UUID
    public var results: [FileMoveResult]
    public var cancelled: Bool

    public init(batchID: UUID, results: [FileMoveResult], cancelled: Bool) {
        self.batchID = batchID
        self.results = results
        self.cancelled = cancelled
    }

    public var succeeded: Int { results.filter { $0.status == .success }.count }
    public var failed: Int { results.filter { $0.status == .failed }.count }
    public var skipped: Int { results.filter { $0.status == .skipped }.count }
    public var needsDecision: Int { results.filter { $0.status == .needsDecision }.count }
}

public struct OrganizeExecution: Sendable {
    public var progress: AsyncStream<OrganizeProgress>
    public var result: Task<BatchResult, Never>

    public init(progress: AsyncStream<OrganizeProgress>, result: Task<BatchResult, Never>) {
        self.progress = progress
        self.result = result
    }

    public func cancel() {
        result.cancel()
    }
}
