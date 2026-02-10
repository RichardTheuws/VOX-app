import SwiftUI

/// Command history window with search and filtering.
struct HistoryView: View {
    @ObservedObject var history: CommandHistory
    @State private var searchText = ""
    @State private var filterStatus: CommandStatus?
    @State private var expandedCommandID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search commands...", text: $searchText)
                    .textFieldStyle(.plain)

                Picker("Filter", selection: $filterStatus) {
                    Text("All").tag(nil as CommandStatus?)
                    Text("Success").tag(CommandStatus.success as CommandStatus?)
                    Text("Error").tag(CommandStatus.error as CommandStatus?)
                }
                .frame(width: 100)
            }
            .padding(12)

            Divider()

            // Command list
            if filteredGroups.isEmpty {
                VStack {
                    Spacer()
                    Text("No commands yet")
                        .foregroundColor(.secondary)
                    Text("Press ⌥Space to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(filteredGroups, id: \.0) { dayLabel, commands in
                            Section {
                                ForEach(commands) { command in
                                    CommandRow(
                                        command: command,
                                        isExpanded: expandedCommandID == command.id,
                                        onToggleExpand: {
                                            withAnimation {
                                                expandedCommandID = expandedCommandID == command.id ? nil : command.id
                                            }
                                        }
                                    )
                                    Divider()
                                }
                            } header: {
                                Text(dayLabel)
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.bar)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Clear History") {
                    history.clear()
                }
                .foregroundColor(.statusRed)
                .font(.caption)

                Spacer()

                Text("Showing \(totalFilteredCount) commands")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .frame(width: 480, height: 500)
    }

    // MARK: - Filtering

    private var filteredGroups: [(String, [VoxCommand])] {
        history.groupedByDay.compactMap { (label, commands) in
            let filtered = commands.filter { command in
                let matchesSearch = searchText.isEmpty ||
                    command.transcription.localizedCaseInsensitiveContains(searchText) ||
                    command.resolvedCommand.localizedCaseInsensitiveContains(searchText)

                let matchesFilter = filterStatus == nil || command.status == filterStatus

                return matchesSearch && matchesFilter
            }

            return filtered.isEmpty ? nil : (label, filtered)
        }
    }

    private var totalFilteredCount: Int {
        filteredGroups.reduce(0) { $0 + $1.1.count }
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: VoxCommand
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(command.formattedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .leading)

                Text(command.statusIcon)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\"\(command.transcription)\"")
                        .font(.caption)
                        .lineLimit(isExpanded ? nil : 1)

                    Text("→ \(command.target.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let summary = command.summary {
                        Text(summary)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: { copyCommand() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy command")

                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse" : "Expand")
                }
            }

            // Expanded output
            if isExpanded, let output = command.output {
                Text(output)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.leading, 56)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.resolvedCommand, forType: .string)
    }
}
