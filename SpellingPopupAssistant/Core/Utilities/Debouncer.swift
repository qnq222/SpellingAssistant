import Foundation

final class Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
    }
}
