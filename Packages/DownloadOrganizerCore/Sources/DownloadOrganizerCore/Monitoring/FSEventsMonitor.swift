import CoreServices
import Foundation

public struct FSEventsMonitor: FileEventSource {
    public init() {}

    public func events(for root: URL, since eventID: UInt64?) -> AsyncStream<FileEvent> {
        AsyncStream { continuation in
            let box = EventBridge(continuation: continuation)
            let retained = Unmanaged.passRetained(box)
            var context = FSEventStreamContext(
                version: 0,
                info: retained.toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let since = FSEventStreamEventId(eventID ?? UInt64(kFSEventStreamEventIdSinceNow))
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagNoDefer
            )
            guard let stream = FSEventStreamCreate(
                nil,
                Self.callback,
                &context,
                [root.path] as CFArray,
                since,
                0,
                flags
            ) else {
                retained.release()
                continuation.finish()
                return
            }
            let queue = DispatchQueue(label: "downloadorganizer.fsevents")
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            let handle = StreamHandle(stream: stream, bridge: retained)
            continuation.onTermination = { _ in
                handle.stop()
            }
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, eventIds in
        guard let info else { return }
        let bridge = Unmanaged<EventBridge>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        let count = min(numEvents, paths.count)
        for index in 0..<count {
            let flags = eventFlags[index]
            var mapped = FileEventFlag()
            if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { mapped.insert(.created) }
            if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { mapped.insert(.removed) }
            if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { mapped.insert(.renamed) }
            if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 { mapped.insert(.modified) }
            if flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 { mapped.insert(.isDirectory) }
            bridge.continuation.yield(
                FileEvent(path: paths[index], eventID: eventIds[index], flags: mapped)
            )
        }
    }
}

private final class EventBridge: @unchecked Sendable {
    let continuation: AsyncStream<FileEvent>.Continuation

    init(continuation: AsyncStream<FileEvent>.Continuation) {
        self.continuation = continuation
    }
}

private final class StreamHandle: @unchecked Sendable {
    private let stream: FSEventStreamRef
    private let bridge: Unmanaged<EventBridge>
    private let lock = NSLock()
    private var stopped = false

    init(stream: FSEventStreamRef, bridge: Unmanaged<EventBridge>) {
        self.stream = stream
        self.bridge = bridge
    }

    func stop() {
        lock.lock()
        let shouldStop = !stopped
        stopped = true
        lock.unlock()
        guard shouldStop else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        bridge.release()
    }
}
