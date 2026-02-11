import Foundation

/// HTTP client for Ollama API — handles summarization, model management, and server status.
/// Ollama runs locally at http://localhost:11434 by default.
@MainActor
final class OllamaService: ObservableObject {
    @Published var isServerRunning = false
    @Published var availableModels: [OllamaModel] = []
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0

    private let settings: VoxSettings
    private let session: URLSession

    init(settings: VoxSettings = .shared) {
        self.settings = settings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Server Status

    /// Check if Ollama server is running by querying /api/tags.
    @discardableResult
    func checkServer() async -> Bool {
        guard let url = URL(string: "\(settings.ollamaURL)/api/tags") else {
            isServerRunning = false
            return false
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isServerRunning = false
                return false
            }

            // Parse models while we're at it
            if let tagsResponse = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data) {
                availableModels = tagsResponse.models
            }

            isServerRunning = true
            return true
        } catch {
            isServerRunning = false
            return false
        }
    }

    /// Check if the configured model is available locally.
    func isModelAvailable() async -> Bool {
        let running = await checkServer()
        guard running else { return false }
        let target = settings.ollamaModel.lowercased()
        return availableModels.contains { $0.name.lowercased().hasPrefix(target) }
    }

    // MARK: - Summarization

    /// Summarize terminal output using Ollama's generate API.
    /// Returns nil if the request fails (caller should fall back to heuristic).
    nonisolated func summarize(text: String, command: String, maxSentences: Int, language: String) async -> String? {
        let settings = await MainActor.run { self.settings }
        let baseURL = await MainActor.run { settings.ollamaURL }
        let model = await MainActor.run { settings.ollamaModel }

        guard let url = URL(string: "\(baseURL)/api/generate") else { return nil }

        let languageName: String
        switch language {
        case "nl": languageName = "Dutch"
        case "de": languageName = "German"
        default: languageName = "English"
        }

        let prompt = """
        Summarize this terminal output in \(maxSentences) sentence\(maxSentences == 1 ? "" : "s"). \
        Respond ONLY in \(languageName). Be concise and focus on the result, not the process. \
        The command was: \(command)

        Terminal output:
        \(String(text.prefix(4000)))
        """

        let requestBody = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let result = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            let summary = result.response.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        } catch {
            return nil
        }
    }

    // MARK: - Model Management

    /// Pull (download) a model from Ollama registry with progress tracking.
    func pullModel(_ name: String) async throws {
        guard let url = URL(string: "\(settings.ollamaURL)/api/pull") else {
            throw OllamaError.invalidURL
        }

        isDownloadingModel = true
        downloadProgress = 0

        defer {
            isDownloadingModel = false
        }

        let requestBody = OllamaPullRequest(name: name)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600 // 10 min for large models

        request.httpBody = try JSONEncoder().encode(requestBody)

        // Use streaming to track progress
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.pullFailed
        }

        var buffer = Data()
        for try await byte in bytes {
            buffer.append(byte)

            // Ollama streams JSON lines separated by newlines
            if byte == UInt8(ascii: "\n") {
                if let progress = try? JSONDecoder().decode(OllamaPullProgress.self, from: buffer) {
                    if let total = progress.total, total > 0, let completed = progress.completed {
                        downloadProgress = Double(completed) / Double(total)
                    }
                    if progress.status == "success" {
                        downloadProgress = 1.0
                    }
                }
                buffer = Data()
            }
        }

        // Refresh model list
        await checkServer()
    }

    // MARK: - Installation Check

    /// Check if Ollama binary is installed on this machine.
    static func isOllamaInstalled() -> Bool {
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// URL to download Ollama.
    static var downloadURL: URL {
        URL(string: "https://ollama.com/download")!
    }
}

// MARK: - API Models

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

struct OllamaModel: Decodable, Identifiable {
    let name: String
    let size: Int64?
    let modifiedAt: String?

    var id: String { name }

    /// Human-readable size (e.g. "2.0 GB").
    var formattedSize: String {
        guard let size else { return "?" }
        let gb = Double(size) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    enum CodingKeys: String, CodingKey {
        case name, size
        case modifiedAt = "modified_at"
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct OllamaPullRequest: Encodable {
    let name: String
}

private struct OllamaPullProgress: Decodable {
    let status: String
    let total: Int64?
    let completed: Int64?
}

enum OllamaError: Error, LocalizedError {
    case invalidURL
    case pullFailed
    case serverNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Ollama URL"
        case .pullFailed: "Failed to download model"
        case .serverNotRunning: "Ollama server is not running"
        }
    }
}
