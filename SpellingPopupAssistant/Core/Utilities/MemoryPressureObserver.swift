import Foundation

final class MemoryPressureObserver {
    private var source: DispatchSourceMemoryPressure?
    private let queue = DispatchQueue(label: "SpellingPopupAssistant.MemoryPressure", qos: .utility)
    private let onPressure: () -> Void

    init(onPressure: @escaping () -> Void) {
        self.onPressure = onPressure
    }

    func start() {
        guard source == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: queue
        )
        source.setEventHandler { [onPressure] in
            onPressure()
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
