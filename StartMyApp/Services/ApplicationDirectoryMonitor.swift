import Foundation
import CoreServices

/// Monitors application directories for changes using FSEvents API
final class ApplicationDirectoryMonitor {
    private var eventStream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.startmyapp.directorymonitor", qos: .utility)
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
    }

    /// Start monitoring the application directories
    func startMonitoring() {
        guard eventStream == nil else {
            print("⚠️ Directory monitor already running")
            return
        }

        let pathsToWatch = monitoredPaths as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
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
            let monitor = Unmanaged<ApplicationDirectoryMonitor>.fromOpaque(info).takeUnretainedValue()
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
            print("❌ Failed to create FSEvent stream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)

        if FSEventStreamStart(stream) {
            print("✅ Application directory monitor started")
            print("   Monitoring paths:")
            for path in monitoredPaths {
                print("   - \(path)")
            }
        } else {
            print("❌ Failed to start FSEvent stream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    /// Stop monitoring the application directories
    func stopMonitoring() {
        guard let stream = eventStream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil

        // Cancel any pending debounce timer
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingChangedAppPaths.removeAll()

        print("🛑 Application directory monitor stopped")
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
                    print("📁 Detected app change: \(path)")
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
            print("🔄 \(paths.count) application bundle(s) changed, incrementally refreshing...")
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
