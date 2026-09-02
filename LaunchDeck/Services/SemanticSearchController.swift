import Combine
import Foundation
import LaunchDeckCore
import OSLog

private nonisolated let semanticControllerLogger = Logger(subsystem: "com.everettjf.launchdeck", category: "IntentSearch")

@MainActor
final class SemanticSearchController: ObservableObject {
    @Published private(set) var results: [IntentRecommendation] = []
    @Published private(set) var phase: IntentSearchPhase = .idle
    @Published private(set) var availability: IntentSearchAvailability = .checking
    var candidatesProvider: (String) -> [SearchItemCandidate] = { _ in [] }

    private let searcher: any IntentSearching
    private let debounce: Duration
    private let timeout: Duration
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    init(searcher: (any IntentSearching)? = nil,
         debounce: Duration = .milliseconds(350),
         timeout: Duration = .seconds(6)) {
        self.searcher = searcher ?? IntentSearcherFactory.make()
        self.debounce = debounce
        self.timeout = timeout
    }

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }
    var isSearching: Bool { phase == .waiting || phase == .searching }

    func initialize() {
        Task { availability = await searcher.availability() }
    }

    func handleQueryChange(_ rawQuery: String) {
        generation += 1
        let requestGeneration = generation
        searchTask?.cancel()
        guard rawQuery.hasPrefix("/") else { reset(); return }
        let query = String(rawQuery.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { reset(); return }
        guard isAvailable else { results = []; phase = .idle; return }

        let debounce = self.debounce
        let timeout = self.timeout
        phase = .waiting
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                guard !Task.isCancelled, let self, requestGeneration == self.generation else { return }
                self.phase = .searching
                let startedAt = ContinuousClock.now
                let candidates = self.candidatesProvider(query)
                let found = try await withThrowingTaskGroup(of: [IntentRecommendation].self) { group in
                    group.addTask { try await self.searcher.search(query: query, candidates: candidates) }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        throw IntentSearchTimeout()
                    }
                    let first = try await group.next() ?? []
                    group.cancelAll()
                    return first
                }
                guard !Task.isCancelled, requestGeneration == self.generation else { return }
                self.results = found
                self.phase = .completed
                semanticControllerLogger.info("Intent search completed candidates=\(candidates.count) results=\(found.count) duration=\(Self.milliseconds(startedAt.duration(to: .now)), format: .fixed(precision: 1))ms")
            } catch is CancellationError {
                return
            } catch {
                guard requestGeneration == self?.generation else { return }
                self?.results = []
                self?.phase = .failed(error.localizedDescription)
                semanticControllerLogger.error("Intent search failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func reset() {
        searchTask?.cancel()
        searchTask = nil
        if !results.isEmpty { results = [] }
        phase = .idle
    }

    nonisolated private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private struct IntentSearchTimeout: LocalizedError {
    var errorDescription: String? { "Intent search timed out. Local results are still available." }
}
