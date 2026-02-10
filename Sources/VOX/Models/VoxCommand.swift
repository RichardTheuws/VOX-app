import Foundation

/// A single voice command with its execution result.
struct VoxCommand: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let transcription: String
    let resolvedCommand: String
    let target: TargetApp
    var status: CommandStatus
    var output: String?
    var summary: String?
    var exitCode: Int32?
    var duration: TimeInterval?

    init(
        transcription: String,
        resolvedCommand: String,
        target: TargetApp
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.transcription = transcription
        self.resolvedCommand = resolvedCommand
        self.target = target
        self.status = .pending
    }

    var isSuccess: Bool {
        status == .success
    }

    var isError: Bool {
        status == .error
    }

    var statusIcon: String {
        switch status {
        case .pending: "⏳"
        case .running: "🔵"
        case .success: "🟢"
        case .error: "🔴"
        case .cancelled: "⚪"
        case .timeout: "🟡"
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

enum CommandStatus: String, Codable {
    case pending
    case running
    case success
    case error
    case cancelled
    case timeout
}
