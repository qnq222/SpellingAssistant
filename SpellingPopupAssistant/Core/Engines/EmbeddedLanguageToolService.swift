import Darwin
import Foundation

final class EmbeddedLanguageToolService: LanguageToolServing {
    static let shared = EmbeddedLanguageToolService()

    private struct CheckResponse: Decodable {
        let matches: [Match]
    }

    private struct Match: Decodable {
        let message: String
        let shortMessage: String?
        let offset: Int
        let length: Int
        let replacements: [Replacement]
        let rule: Rule
    }

    private struct Replacement: Decodable {
        let value: String
    }

    private struct Rule: Decodable {
        let id: String
        let issueType: String?
        let category: Category
    }

    private struct Category: Decodable {
        let id: String
        let name: String
    }

    private let resourcesURL: URL
    private let session: URLSession
    private let readinessTimeout: TimeInterval
    private var process: Process?
    private var port: UInt16?

    private(set) var resourceUsage: EngineResourceUsage?

    var isRunning: Bool {
        process?.isRunning == true
    }

    init(
        resourcesURL: URL = Bundle.main.resourceURL ?? URL(fileURLWithPath: ""),
        session: URLSession = .shared,
        readinessTimeout: TimeInterval = 12
    ) {
        self.resourcesURL = resourcesURL
        self.session = session
        self.readinessTimeout = readinessTimeout
    }

    func start() async throws {
        guard !isRunning else { return }

        let javaURL = resourcesURL.appendingPathComponent("JavaRuntime/bin/java")
        let serverJarURL = resourcesURL.appendingPathComponent("LanguageTool/languagetool-server.jar")
        try requireExistingFile(javaURL)
        try requireExistingFile(serverJarURL)

        let port = try Self.availablePort()
        let process = Process()
        process.executableURL = javaURL
        process.currentDirectoryURL = resourcesURL.appendingPathComponent("LanguageTool")
        process.arguments = [
            "-Xms32m",
            "-Xmx160m",
            "-XX:+UseSerialGC",
            "-Dfile.encoding=UTF-8",
            "-jar",
            serverJarURL.path,
            "--port",
            String(port),
            "--public",
            "false"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw LanguageToolError.processFailedToStart
        }

        self.process = process
        self.port = port

        do {
            try await waitUntilReady(port: port)
        } catch {
            stop()
            throw error
        }
    }

    func analyze(text: String) async throws -> CorrectionResult {
        guard let port else { throw LanguageToolError.serverUnavailable }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/v2/check"

        guard let url = components.url else {
            throw LanguageToolError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "text": text,
            "language": "en-US",
            "preferredVariants": "en-US",
            "level": "default",
            "enabledOnly": "false",
            "disabledCategories": "STYLE,COLLOQUIALISMS,REDUNDANCY"
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw LanguageToolError.invalidResponse
        }

        resourceUsage = currentResourceUsage()
        return try correctionResult(fromLanguageToolResponse: data, originalText: text)
    }

    func correctionResult(fromLanguageToolResponse data: Data, originalText: String) throws -> CorrectionResult {
        let checkResponse = try JSONDecoder().decode(CheckResponse.self, from: data)
        return makeCorrectionResult(from: checkResponse.matches, originalText: originalText)
    }

    func stop() {
        guard let process else { return }
        process.terminate()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                process.interrupt()
            }
        }

        self.process = nil
        self.port = nil
        self.resourceUsage = nil
    }

    private func waitUntilReady(port: UInt16) async throws {
        let deadline = Date().addingTimeInterval(readinessTimeout)

        while Date() < deadline {
            guard isRunning else {
                throw LanguageToolError.processFailedToStart
            }

            if await isServerReady(port: port) {
                return
            }

            try await Task.sleep(for: .milliseconds(150))
        }

        throw LanguageToolError.serverUnavailable
    }

    private func isServerReady(port: UInt16) async -> Bool {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/v2/languages"

        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return 200..<300 ~= httpResponse.statusCode
        } catch {
            return false
        }
    }

    private func makeCorrectionResult(from matches: [Match], originalText: String) -> CorrectionResult {
        let nsText = originalText as NSString
        let usableMatches = nonOverlappingMatches(from: matches.filter { match in
            match.offset >= 0
                && match.length > 0
                && match.offset + match.length <= nsText.length
                && !match.replacements.isEmpty
        })

        var correctedText = originalText
        var corrections: [WordCorrection] = []
        var issues: [CorrectionIssue] = []
        var spellingIssueCount = 0
        var grammarIssueCount = 0

        for match in usableMatches {
            let original = nsText.substring(with: NSRange(location: match.offset, length: match.length))
            let replacement = preferredReplacement(for: match, original: original)
            let kind = issueKind(for: match)

            switch kind {
            case .spelling:
                spellingIssueCount += 1
            case .grammar:
                grammarIssueCount += 1
            }

            if let replacement, !replacement.isEmpty, replacement != original {
                corrections.append(WordCorrection(original: original, corrected: replacement))
            }

            issues.append(
                CorrectionIssue(
                    kind: kind,
                    original: original,
                    replacement: replacement,
                    message: match.shortMessage?.isEmpty == false ? match.shortMessage ?? match.message : match.message
                )
            )
        }

        for match in usableMatches.sorted(by: { $0.offset > $1.offset }) {
            let range = NSRange(location: match.offset, length: match.length)
            let original = nsText.substring(with: range)
            guard let replacement = preferredReplacement(for: match, original: original) else { continue }
            correctedText = (correctedText as NSString).replacingCharacters(in: range, with: replacement)
        }

        return CorrectionResult(
            originalText: originalText,
            correctedText: correctedText,
            spellingIssueCount: spellingIssueCount,
            grammarIssueCount: grammarIssueCount,
            misspelledWordCount: spellingIssueCount,
            corrections: corrections,
            issues: issues
        )
    }

    private func nonOverlappingMatches(from matches: [Match]) -> [Match] {
        var accepted: [Match] = []
        let rankedMatches = matches.sorted { lhs, rhs in
            if lhs.offset != rhs.offset {
                return lhs.offset < rhs.offset
            }

            return lhs.length > rhs.length
        }

        for match in rankedMatches {
            let range = NSRange(location: match.offset, length: match.length)
            let overlapsAcceptedMatch = accepted.contains { acceptedMatch in
                NSIntersectionRange(range, NSRange(location: acceptedMatch.offset, length: acceptedMatch.length)).length > 0
            }

            if !overlapsAcceptedMatch {
                accepted.append(match)
            }
        }

        return accepted
    }

    private func preferredReplacement(for match: Match, original: String) -> String? {
        match.replacements
            .map(\.value)
            .first { !$0.isEmpty && $0 != original }
    }

    private func issueKind(for match: Match) -> CorrectionIssue.IssueKind {
        let issueType = match.rule.issueType?.lowercased() ?? ""
        let categoryID = match.rule.category.id.uppercased()

        if issueType.contains("misspelling")
            || issueType.contains("typographical")
            || categoryID.contains("TYPOS")
            || categoryID.contains("TYPOGRAPHY")
        {
            return .spelling
        }

        return .grammar
    }

    private func formBody(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func requireExistingFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LanguageToolError.missingBundleResource(url.path)
        }
    }

    private func currentResourceUsage() -> EngineResourceUsage? {
        guard let processIdentifier = process?.processIdentifier else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "rss=", "-p", String(processIdentifier)]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let text = String(data: data, encoding: .utf8),
                let rssKilobytes = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return nil
            }

            return EngineResourceUsage(residentMemoryBytes: rssKilobytes * 1024, sampledAt: Date())
        } catch {
            return nil
        }
    }

    private static func availablePort() throws -> UInt16 {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw LanguageToolError.processFailedToStart }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else { throw LanguageToolError.processFailedToStart }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }

        guard nameResult == 0 else { throw LanguageToolError.processFailedToStart }
        return UInt16(bigEndian: boundAddress.sin_port)
    }
}
