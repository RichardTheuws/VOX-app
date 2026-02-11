import Foundation

/// The 4 verbosity levels that control how much audio feedback VOX provides.
enum VerbosityLevel: Int, CaseIterable, Codable, Identifiable {
    case silent = 0
    case notice = 1
    case summary = 2
    case full = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .silent: "Silent"
        case .notice: "Notice"
        case .summary: "Summary"
        case .full: "Full"
        }
    }

    var description: String {
        switch self {
        case .silent: "No audio — visual indicator only"
        case .notice: "Ready notification in your language"
        case .summary: "1-2 sentence AI summary"
        case .full: "Complete cleaned response read aloud"
        }
    }

    var dots: String {
        let filled = rawValue + 1
        let empty = VerbosityLevel.allCases.count - filled
        return String(repeating: "●", count: filled) + String(repeating: "○", count: empty)
    }

    func next() -> VerbosityLevel {
        let nextRaw = (rawValue + 1) % VerbosityLevel.allCases.count
        return VerbosityLevel(rawValue: nextRaw) ?? .silent
    }
}
