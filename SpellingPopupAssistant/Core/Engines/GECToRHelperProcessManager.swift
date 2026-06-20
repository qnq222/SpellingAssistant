import Darwin
import Foundation

final class GECToRHelperProcessManager {
    static let shared = GECToRHelperProcessManager()

    private let scriptURL: URL
    private let projectRootURL: URL
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    init(
        scriptURL: URL = GECToRHelperProcessManager.defaultScriptURL(),
        projectRootURL: URL = GECToRHelperProcessManager.defaultProjectRootURL()
    ) {
        self.scriptURL = scriptURL
        self.projectRootURL = projectRootURL
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(endpoint: String) {
        guard !isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) || FileManager.default.fileExists(atPath: scriptURL.path) else {
            Logger.correction.error("GECToR helper script is missing: \(self.scriptURL.path, privacy: .public)")
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.currentDirectoryURL = projectRootURL
        process.arguments = [scriptURL.path]
        process.environment = environment(for: endpoint)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
                return
            }
            Logger.correction.info("GECToR helper: \(message, privacy: .public)")
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
                return
            }
            Logger.correction.error("GECToR helper: \(message, privacy: .public)")
        }

        process.terminationHandler = { [weak self] process in
            Logger.correction.info("GECToR helper exited with status \(process.terminationStatus, privacy: .public)")
            self?.clearProcessIfCurrent(process)
        }

        do {
            try process.run()
            self.process = process
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            Logger.correction.info("Started GECToR helper in the background.")
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            Logger.correction.error("Failed to start GECToR helper: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard let process else { return }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [process] in
                guard process.isRunning else { return }
                kill(process.processIdentifier, SIGKILL)
            }
        }

        self.process = nil
        outputPipe = nil
        errorPipe = nil
    }

    private func environment(for endpoint: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        if let url = URL(string: endpoint) {
            if let host = url.host, !host.isEmpty {
                environment["GECTOR_HOST"] = host
            }
            if let port = url.port {
                environment["GECTOR_PORT"] = String(port)
            }
        }

        return environment
    }

    private func clearProcessIfCurrent(_ completedProcess: Process) {
        guard process === completedProcess else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
    }

    private static func defaultScriptURL() -> URL {
        defaultProjectRootURL()
            .appendingPathComponent("scripts")
            .appendingPathComponent("gector_helper")
            .appendingPathComponent("run_roberta_helper.sh")
    }

    private static func defaultProjectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
