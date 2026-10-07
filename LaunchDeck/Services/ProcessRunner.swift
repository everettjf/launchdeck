import Foundation

/// Runs a command-line tool without blocking the calling actor.
///
/// Standard error is drained while the process runs, so a chatty tool cannot fill the pipe
/// buffer and deadlock. Cancelling the calling task terminates the process.
nonisolated enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let standardError: String
        var succeeded: Bool { status == 0 }
    }

    static func run(executable: String, arguments: [String]) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        let box = ProcessBox(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if box.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: Result(status: process.terminationStatus,
                                                              standardError: String(decoding: data, as: UTF8.self)))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}

private nonisolated final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false

    init(_ process: Process) { self.process = process }

    var wasCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        if process.isRunning { process.terminate() }
    }
}
