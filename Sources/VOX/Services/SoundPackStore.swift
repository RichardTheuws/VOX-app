import Foundation
import AppKit
import AVFoundation

/// Search result from an online sound source.
struct SoundSearchResult: Identifiable {
    let id: String           // Slug (unique per sound)
    let title: String
    let slug: String         // URL slug, e.g. "warcraft-peon-work-work"
    var mp3URL: URL?         // Resolved lazily from detail page
    let source: String       // "MyInstants"

    /// URL for the detail page of this sound.
    var detailURL: URL {
        URL(string: "https://www.myinstants.com/en/instant/\(slug)/")!
    }
}

/// Category assignment for building a pack.
enum SoundCategory: String, CaseIterable {
    case success
    case error
}

/// Item staged for download in the pack builder.
struct StagedSound: Identifiable {
    let id = UUID()
    let result: SoundSearchResult
    let category: SoundCategory
}

/// Manages searching, previewing, and downloading sounds from MyInstants.
/// Uses direct HTML scraping — no third-party API dependency.
@MainActor
final class SoundPackStore: ObservableObject {
    @Published var searchResults: [SoundSearchResult] = []
    @Published var isSearching = false
    @Published var stagedSounds: [StagedSound] = []
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    private let session: URLSession
    private var mp3URLCache: [String: URL] = [:]

    private static let baseURL = "https://www.myinstants.com"
    private static let searchPath = "/en/search/?name="

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search

    /// Search MyInstants for sounds matching the query.
    /// Parses search results page HTML for titles and slugs.
    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        error = nil
        defer { isSearching = false }

        do {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let urlString = "\(Self.baseURL)\(Self.searchPath)\(encoded)"
            guard let url = URL(string: urlString) else {
                self.error = "Invalid search URL"
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.error = "Search failed (server error)"
                searchResults = []
                return
            }

            guard let html = String(data: data, encoding: .utf8) else {
                self.error = "Could not decode response"
                searchResults = []
                return
            }

            searchResults = parseSearchResults(html: html)
        } catch {
            self.error = "Search failed: \(error.localizedDescription)"
            searchResults = []
        }
    }

    // MARK: - MP3 URL Resolution

    /// Resolve the MP3 download URL for a search result.
    /// Fetches the detail page and extracts `preloadAudioUrl` from the JavaScript.
    func resolveMP3URL(for result: SoundSearchResult) async throws -> URL {
        // Check cache first
        if let cached = mp3URLCache[result.slug] {
            return cached
        }

        var request = URLRequest(url: result.detailURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SoundPackStoreError.invalidResponse
        }

        guard let mp3URL = parseMP3URL(html: html) else {
            throw SoundPackStoreError.mp3NotFound(slug: result.slug)
        }

        mp3URLCache[result.slug] = mp3URL
        return mp3URL
    }

    // MARK: - Staging (pack builder)

    func addToStaged(_ result: SoundSearchResult, category: SoundCategory) {
        // Avoid duplicates (same slug + same category)
        guard !stagedSounds.contains(where: { $0.result.slug == result.slug && $0.category == category }) else { return }
        stagedSounds.append(StagedSound(result: result, category: category))
    }

    func removeFromStaged(_ sound: StagedSound) {
        stagedSounds.removeAll { $0.id == sound.id }
    }

    func clearStaged() {
        stagedSounds.removeAll()
    }

    var stagedSuccessCount: Int {
        stagedSounds.filter { $0.category == .success }.count
    }

    var stagedErrorCount: Int {
        stagedSounds.filter { $0.category == .error }.count
    }

    // MARK: - Install

    /// Download all staged sounds and create a custom sound pack.
    func installPack(name: String, soundPackManager: SoundPackManager) async throws {
        guard !stagedSounds.isEmpty else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SoundPackStoreError.invalidPackName
        }

        isDownloading = true
        downloadProgress = 0
        error = nil
        defer { isDownloading = false }

        // Create pack directory structure
        try soundPackManager.createPackTemplate(name: name)
        let packDir = SoundPackManager.soundPacksDirectory.appendingPathComponent(name)

        let total = Double(stagedSounds.count)
        var failedCount = 0

        for (index, staged) in stagedSounds.enumerated() {
            do {
                // Resolve MP3 URL if not yet known
                let mp3URL = try await resolveMP3URL(for: staged.result)

                // Download the file
                let destDir = packDir.appendingPathComponent(staged.category.rawValue)
                let filename = sanitizeFilename(staged.result.title) + ".mp3"
                let destURL = destDir.appendingPathComponent(filename)

                var request = URLRequest(url: mp3URL)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                request.setValue("\(Self.baseURL)/", forHTTPHeaderField: "Referer")

                let (tempURL, _) = try await session.download(for: request)
                try FileManager.default.moveItem(at: tempURL, to: destURL)
            } catch {
                failedCount += 1
                // Continue with remaining sounds
            }

            downloadProgress = Double(index + 1) / total
        }

        // Refresh pack list
        soundPackManager.scanForPacks()
        stagedSounds.removeAll()

        if failedCount > 0 {
            self.error = "\(failedCount) sound(s) failed to download"
        }
    }

    // MARK: - Preview

    /// Preview a sound by downloading to a temp file and playing locally.
    /// NSSound can't play remote URLs, so we download first.
    /// Returns the local temp URL for duration display.
    @discardableResult
    func preview(_ result: SoundSearchResult, using ttsEngine: TTSEngine) async -> URL? {
        do {
            let mp3URL = try await resolveMP3URL(for: result)

            // Download to temp file — NSSound can't play remote URLs
            var request = URLRequest(url: mp3URL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("\(Self.baseURL)/", forHTTPHeaderField: "Referer")

            let (tempURL, _) = try await session.download(for: request)
            let playURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vox-preview-\(result.slug).mp3")

            // Move to predictable location (cleanup old preview)
            try? FileManager.default.removeItem(at: playURL)
            try FileManager.default.moveItem(at: tempURL, to: playURL)

            ttsEngine.playCustomSound(at: playURL)
            return playURL
        } catch {
            self.error = "Preview failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Audio Duration

    /// Get audio file duration in seconds (synchronous for UI display).
    @available(macOS, deprecated: 13.0, message: "Acceptable: short local files only")
    static func audioDuration(at url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        return (duration.isFinite && duration > 0) ? duration : nil
    }

    /// Format duration as "0:03" or "1:23".
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    // MARK: - HTML Parsing

    /// Parse search results from MyInstants search page HTML.
    /// Extracts title and slug from `<a class="instant-link link-secondary">` tags.
    func parseSearchResults(html: String) -> [SoundSearchResult] {
        var results: [SoundSearchResult] = []

        // Pattern: <a href="/en/instant/{slug}/" ... class="instant-link link-secondary">{title}</a>
        // The href and class may appear in either order, so we match flexibly.
        let pattern = #"<a\s+[^>]*href="(?:https://www\.myinstants\.com)?/en/instant/([^"]+)/"[^>]*class="[^"]*instant-link[^"]*"[^>]*>([^<]+)</a>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return results
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let slugRange = match.range(at: 1)
            let titleRange = match.range(at: 2)

            guard slugRange.location != NSNotFound, titleRange.location != NSNotFound else { continue }

            let slug = nsHTML.substring(with: slugRange)
            let title = nsHTML.substring(with: titleRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")

            guard !slug.isEmpty, !title.isEmpty else { continue }

            // Deduplicate by slug
            guard !results.contains(where: { $0.slug == slug }) else { continue }

            results.append(SoundSearchResult(
                id: slug,
                title: title,
                slug: slug,
                mp3URL: nil,
                source: "MyInstants"
            ))
        }

        // Also try to extract MP3 URLs from the search page if available
        // Pattern: play('/media/sounds/{filename}.mp3') or similar
        extractMP3URLsFromSearchPage(html: html, into: &results)

        return results
    }

    /// Try to extract MP3 URLs directly from the search page HTML.
    /// This avoids needing a separate request per sound for preview/download.
    private func extractMP3URLsFromSearchPage(html: String, into results: inout [SoundSearchResult]) {
        // Look for patterns like: '/media/sounds/filename.mp3'
        let mp3Pattern = #"['"](/media/sounds/[^'"]+\.mp3)['"]"#
        guard let regex = try? NSRegularExpression(pattern: mp3Pattern, options: []) else { return }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

        var mp3Paths: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let pathRange = match.range(at: 1)
            guard pathRange.location != NSNotFound else { continue }
            let path = nsHTML.substring(with: pathRange)
            mp3Paths.append(path)
        }

        // Try to match MP3 paths to results by order (they appear in the same order on the page)
        // This is a best-effort optimization — if it fails, we fall back to detail page fetching
        for (index, path) in mp3Paths.enumerated() {
            guard index < results.count else { break }
            if let fullURL = URL(string: "\(Self.baseURL)\(path)") {
                results[index].mp3URL = fullURL
                mp3URLCache[results[index].slug] = fullURL
            }
        }
    }

    /// Parse MP3 URL from a MyInstants detail page.
    /// Looks for: `var preloadAudioUrl = '/media/sounds/{file}.mp3';`
    func parseMP3URL(html: String) -> URL? {
        // Primary pattern: preloadAudioUrl variable
        let patterns = [
            #"preloadAudioUrl\s*=\s*['"]([^'"]+)['"]"#,
            #"['"](/media/sounds/[^'"]+\.mp3)['"]"#,
        ]

        let nsHTML = html as NSString

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

            if let match = matches.first, match.numberOfRanges >= 2 {
                let pathRange = match.range(at: 1)
                guard pathRange.location != NSNotFound else { continue }
                let path = nsHTML.substring(with: pathRange)

                // Build full URL
                if path.hasPrefix("http") {
                    return URL(string: path)
                } else {
                    return URL(string: "\(Self.baseURL)\(path)")
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    /// Sanitize a string for use as a filename.
    func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        let sanitized = name.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
        return String(sanitized.prefix(50)).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Errors

enum SoundPackStoreError: LocalizedError {
    case invalidResponse
    case mp3NotFound(slug: String)
    case invalidPackName

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not decode response from sound source"
        case .mp3NotFound(let slug):
            return "Could not find audio file for '\(slug)'"
        case .invalidPackName:
            return "Pack name cannot be empty"
        }
    }
}
