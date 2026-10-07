import Foundation
import CoreServices
import OSLog
import LaunchDeckCore

private nonisolated let logger = Logger(subsystem: "LaunchDeck", category: "DirectoryMonitor")

/// Monitors application directories for changes using FSEvents API.
/// nonisolated: FSEvents callbacks arrive on a private serial queue, and every piece of
/// mutable state (stream, debounce item, pending paths) is only touched on that queue.
nonisolated final class ApplicationDirectoryMonitor {
    private var eventStream: FSEventStreamRef?
    private var callbackBox: Unmanaged<CallbackBox>?
    private let queue = DispatchQueue(label: "com.launchdeck.directorymonitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private let callback: ([String]) -> Void
    private var debounceWorkItem: DispatchWorkItem?
    private var pendingChangedAppPaths = Set<String>()
    private let debounceDelay: TimeInterval = 2.0 // 2 seconds delay to avoid rapid refreshes

    /// Directories to monitor for application changes
    private let monitoredPaths: [String]

    /// Initialize the directory monitor
    /// - Parameters:
    ///   - fileManager: FileManager instance (for testing)
    ///   - callback: Closure to call when directory changes are detected
    init(fileManager: FileManager = .default, onChange callback: @escaping ([String]) -> Void) {
        self.callback = callback

        // Build list of paths to monitor
        var paths: [String] = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]

        // Add user Applications directory
        if let userApplications = try? fileManager.url(for: .applicationDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false) {
            paths.append(userApplications.path)
        } else {
            let homeApplications = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications")
            paths.append(homeApplications.path)
        }

        self.monitoredPaths = paths
        queue.setSpecific(key: queueKey, value: ())
    }

    /// FSEvents holds this box rather than the monitor itself, so a callback that races with
    /// deallocation sees nil instead of a dangling pointer.
    private final class CallbackBox {
        weak var monitor: ApplicationDirectoryMonitor?
        init(_ monitor: ApplicationDirectoryMonitor) { self.monitor = monitor }
    }

    private func onQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil { work() } else { queue.sync(execute: work) }
    }

    /// Start monitoring the application directories
    func startMonitoring() {
        onQueue(startOnQueue)
    }

    private func startOnQueue() {
        guard eventStream == nil else {
            return
        }
        let box = Unmanaged.passRetained(CallbackBox(self))

        let pathsToWatch = monitoredPaths as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: box.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (
            streamRef,
            clientCallBackInfo,
            numEvents,
            eventPaths,
            eventFlags,
            eventIds
        ) in
            guard let info = clientCallBackInfo else { return }
            guard let monitor = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue().monitor else { return }
            monitor.handleFSEvents(numEvents: numEvents, eventPaths: eventPaths, eventFlags: eventFlags)
        }

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = eventStream else {
            logger.error("Failed to create FSEvent stream")
            box.release()
            return
        }
        callbackBox = box

        FSEventStreamSetDispatchQueue(stream, queue)

        if !FSEventStreamStart(stream) {
            logger.error("Failed to start FSEvent stream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
            callbackBox?.release()
            callbackBox = nil
        }
    }

    /// Stop monitoring the application directories
    func stopMonitoring() {
        onQueue(stopOnQueue)
    }

    private func stopOnQueue() {
        guard let stream = eventStream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        callbackBox?.release()
        callbackBox = nil

        // Cancel any pending debounce timer
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingChangedAppPaths.removeAll()
    }

    private func handleFSEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
            return
        }

        // Check if any .app files were created, modified, or removed
        var changedAppPaths = Set<String>()

        for i in 0..<numEvents {
            let path = paths[i]
            let flags = eventFlags[i]

            // Check if the event is related to .app bundles
            if path.hasSuffix(".app") || path.contains(".app/") {
                // Check for relevant events: created, removed, renamed, or modified
                if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
                   flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 ||
                   flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 ||
                   flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                    if let appPath = ApplicationDiscoveryService.applicationBundlePath(from: path) {
                        changedAppPaths.insert(appPath)
                    }
                }
            }
        }

        if !changedAppPaths.isEmpty {
            debounceRefresh(paths: changedAppPaths)
        }
    }

    private func debounceRefresh(paths: Set<String>) {
        pendingChangedAppPaths.formUnion(paths)
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = Array(self.pendingChangedAppPaths)
            self.pendingChangedAppPaths.removeAll()
            self.callback(paths)
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    deinit {
        stopMonitoring()
    }
}

extension ApplicationDirectoryMonitor: @unchecked Sendable {}
