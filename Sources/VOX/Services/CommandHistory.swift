import Foundation

/// Persists command history to disk.
@MainActor
final class CommandHistory: ObservableObject {
    @Published var commands: [VoxCommand] = []

    private let maxHistoryItems = 500
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voxDir = appSupport.appendingPathComponent("VOX", isDirectory: true)
        try? FileManager.default.createDirectory(at: voxDir, withIntermediateDirectories: true)
        self.storageURL = voxDir.appendingPathComponent("history.json")

        load()
    }

    func add(_ command: VoxCommand) {
        commands.insert(command, at: 0)

        // Trim to max size
        if commands.count > maxHistoryItems {
            commands = Array(commands.prefix(maxHistoryItems))
        }

        save()
    }

    func update(_ command: VoxCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
            save()
        }
    }

    func clear() {
        commands.removeAll()
        save()
    }

    /// Commands grouped by day for display.
    var groupedByDay: [(String, [VoxCommand])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: commands) { command in
            calendar.startOfDay(for: command.timestamp)
        }

        return grouped.sorted { $0.key > $1.key }.map { (date, cmds) in
            let label = dayLabel(for: date)
            return (label, cmds.sorted { $0.timestamp > $1.timestamp })
        }
    }

    // MARK: - Private

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(commands) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([VoxCommand].self, from: data) {
            commands = loaded
        }
    }
}
