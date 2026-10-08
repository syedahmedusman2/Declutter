import Darwin
import Foundation

public enum StabilityResult: Sendable, Equatable {
    case stable(FileSnapshot)
    case temporary
    case disappeared
    case changing
    case busy
}

public protocol StabilityProbing: Sendable {
    func probe(_ url: URL) throws -> FileAttributes?
    func isBusy(_ url: URL) -> Bool
}

public struct FileSystemStabilityProbe: StabilityProbing {
    private let fileSystem: any FileSystemProviding

    public init(fileSystem: any FileSystemProviding) {
        self.fileSystem = fileSystem
    }

    public func probe(_ url: URL) throws -> FileAttributes? {
        guard fileSystem.fileExists(at: url) else { return nil }
        return try fileSystem.attributes(of: url, keys: Set(FileScanner.resourceKeys))
    }

    public func isBusy(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC)
        if fd >= 0 {
            close(fd)
            return false
        }
        return errno == EAGAIN || errno == EWOULDBLOCK || errno == EBUSY
    }
}

public struct StabilityChecker: Sendable {
    private let probe: any StabilityProbing
    private let clock: any OrganizerClock
    public let delay: TimeInterval

    public init(probe: any StabilityProbing, clock: any OrganizerClock, delay: TimeInterval = 2) {
        self.probe = probe
        self.clock = clock
        self.delay = delay
    }

    public func waitUntilStable(_ url: URL) async -> StabilityResult {
        if FileScanner.isTemporaryDownload(url.lastPathComponent) {
            return .temporary
        }
        let first: FileAttributes
        do {
            guard let attributes = try probe.probe(url) else { return .disappeared }
            first = attributes
        } catch {
            return .disappeared
        }
        if first.isDirectory && !first.isPackage {
            return .temporary
        }
        let started = await clock.now()
        do {
            try await clock.sleep(until: started.addingTimeInterval(delay))
        } catch {
            return .disappeared
        }
        if Task.isCancelled { return .disappeared }
        let second: FileAttributes
        do {
            guard let attributes = try probe.probe(url) else { return .disappeared }
            second = attributes
        } catch {
            return .disappeared
        }
        if probe.isBusy(url) { return .busy }
        if second.size != first.size || second.modified != first.modified {
            return .changing
        }
        return .stable(snapshot(url: url, attributes: second))
    }

    private func snapshot(url: URL, attributes: FileAttributes) -> FileSnapshot {
        let name = url.lastPathComponent
        let ext = url.pathExtension
        let nameWithoutExt = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        return FileSnapshot(
            url: url,
            name: name,
            nameWithoutExt: nameWithoutExt,
            ext: ext,
            utType: attributes.typeIdentifier,
            size: attributes.size,
            created: attributes.created,
            modified: attributes.modified,
            fileID: attributes.fileIdentifier,
            isDirectory: attributes.isDirectory,
            isSymlink: attributes.isSymlink,
            isHidden: attributes.isHidden,
            isPackage: attributes.isPackage
        )
    }
}
