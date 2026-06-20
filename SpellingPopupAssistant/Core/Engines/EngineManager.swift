import Foundation

protocol LanguageToolServing: AnyObject {
    var isRunning: Bool { get }
    var resourceUsage: EngineResourceUsage? { get }

    func start() async throws
    func analyze(text: String) async throws -> CorrectionResult
    func stop()
}

actor EngineManager {
    static let shared = EngineManager(service: EmbeddedLanguageToolService.shared)

    private let service: LanguageToolServing
    private let inactivityTimeout: TimeInterval
    private var shutdownTask: Task<Void, Never>?
    private var lastUsedAt: Date?

    init(service: LanguageToolServing, inactivityTimeout: TimeInterval = 60) {
        self.service = service
        self.inactivityTimeout = inactivityTimeout
    }

    var isRunning: Bool {
        service.isRunning
    }

    var currentResourceUsage: EngineResourceUsage? {
        service.resourceUsage
    }

    func analyze(text: String) async throws -> CorrectionResult {
        shutdownTask?.cancel()

        if !service.isRunning {
            try await service.start()
        }

        lastUsedAt = Date()
        let result = try await service.analyze(text: text)
        lastUsedAt = Date()
        scheduleShutdown()
        return result
    }

    func shutdownNow() {
        shutdownTask?.cancel()
        shutdownTask = nil
        service.stop()
    }

    private func scheduleShutdown() {
        shutdownTask?.cancel()
        let timeout = inactivityTimeout

        shutdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.shutdownIfIdle(forAtLeast: timeout)
        }
    }

    private func shutdownIfIdle(forAtLeast timeout: TimeInterval) {
        guard let lastUsedAt, Date().timeIntervalSince(lastUsedAt) >= timeout else {
            scheduleShutdown()
            return
        }

        shutdownNow()
    }
}
