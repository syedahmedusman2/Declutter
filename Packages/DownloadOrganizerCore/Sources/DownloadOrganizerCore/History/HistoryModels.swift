import Foundation
import SwiftData

@Model
public final class HistoryRecord {
    public var recordID: UUID
    public var batchID: UUID
    public var createdAt: Date
    public var sourcePath: String
    public var destinationPath: String
    public var originalName: String
    public var finalName: String
    public var categoryName: String
    public var categoryID: UUID?
    public var ruleSummary: String
    public var statusRaw: String
    public var message: String
    public var undoable: Bool
    public var fileID: String
    public var trashedReplacementPath: String

    public init(
        recordID: UUID,
        batchID: UUID,
        createdAt: Date,
        sourcePath: String,
        destinationPath: String,
        originalName: String,
        finalName: String,
        categoryName: String,
        categoryID: UUID?,
        ruleSummary: String,
        statusRaw: String,
        message: String,
        undoable: Bool,
        fileID: String,
        trashedReplacementPath: String
    ) {
        self.recordID = recordID
        self.batchID = batchID
        self.createdAt = createdAt
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.originalName = originalName
        self.finalName = finalName
        self.categoryName = categoryName
        self.categoryID = categoryID
        self.ruleSummary = ruleSummary
        self.statusRaw = statusRaw
        self.message = message
        self.undoable = undoable
        self.fileID = fileID
        self.trashedReplacementPath = trashedReplacementPath
    }
}

@Model
public final class BatchRecord {
    public var batchID: UUID
    public var createdAt: Date
    public var fileCount: Int

    public init(batchID: UUID, createdAt: Date, fileCount: Int) {
        self.batchID = batchID
        self.createdAt = createdAt
        self.fileCount = fileCount
    }
}

public struct HistoryItem: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var batchID: UUID
    public var createdAt: Date
    public var sourcePath: String
    public var destinationPath: String
    public var originalName: String
    public var finalName: String
    public var categoryName: String
    public var categoryID: UUID?
    public var ruleSummary: String
    public var status: OperationStatus
    public var message: String
    public var undoable: Bool
    public var fileID: String
    public var trashedReplacementPath: String?

    public init(
        id: UUID,
        batchID: UUID,
        createdAt: Date,
        sourcePath: String,
        destinationPath: String,
        originalName: String,
        finalName: String,
        categoryName: String,
        categoryID: UUID?,
        ruleSummary: String,
        status: OperationStatus,
        message: String,
        undoable: Bool,
        fileID: String,
        trashedReplacementPath: String?
    ) {
        self.id = id
        self.batchID = batchID
        self.createdAt = createdAt
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.originalName = originalName
        self.finalName = finalName
        self.categoryName = categoryName
        self.categoryID = categoryID
        self.ruleSummary = ruleSummary
        self.status = status
        self.message = message
        self.undoable = undoable
        self.fileID = fileID
        self.trashedReplacementPath = trashedReplacementPath
    }
}

public struct HistoryQuery: Sendable, Equatable {
    public var text: String
    public var categoryName: String?
    public var status: OperationStatus?
    public var from: Date?
    public var to: Date?
    public var limit: Int

    public init(
        text: String = "",
        categoryName: String? = nil,
        status: OperationStatus? = nil,
        from: Date? = nil,
        to: Date? = nil,
        limit: Int = 500
    ) {
        self.text = text
        self.categoryName = categoryName
        self.status = status
        self.from = from
        self.to = to
        self.limit = limit
    }
}

extension HistoryRecord {
    func apply(_ item: HistoryItem) {
        recordID = item.id
        batchID = item.batchID
        createdAt = item.createdAt
        sourcePath = item.sourcePath
        destinationPath = item.destinationPath
        originalName = item.originalName
        finalName = item.finalName
        categoryName = item.categoryName
        categoryID = item.categoryID
        ruleSummary = item.ruleSummary
        statusRaw = item.status.rawValue
        message = item.message
        undoable = item.undoable
        fileID = item.fileID
        trashedReplacementPath = item.trashedReplacementPath ?? ""
    }

    func item() -> HistoryItem {
        HistoryItem(
            id: recordID,
            batchID: batchID,
            createdAt: createdAt,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            originalName: originalName,
            finalName: finalName,
            categoryName: categoryName,
            categoryID: categoryID,
            ruleSummary: ruleSummary,
            status: OperationStatus(rawValue: statusRaw) ?? .failed,
            message: message,
            undoable: undoable,
            fileID: fileID,
            trashedReplacementPath: trashedReplacementPath.isEmpty ? nil : trashedReplacementPath
        )
    }
}
