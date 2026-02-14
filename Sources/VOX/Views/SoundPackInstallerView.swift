import SwiftUI

/// Sheet view for searching, previewing, and installing sound packs from online sources.
struct SoundPackInstallerView: View {
    @ObservedObject var store: SoundPackStore
    @ObservedObject var soundPackManager: SoundPackManager
    let ttsEngine: TTSEngine
    @Environment(\.dismiss) var dismiss

    @State private var searchQuery = ""
    @State private var packName = ""
    @State private var showSuccessAlert = false

    private let suggestions = ["warcraft peon", "mario", "zelda", "command conquer", "sonic", "pacman", "street fighter"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Search section
            searchSection

            Divider()

            // Results section (scrollable)
            resultsSection

            Divider()

            // Pack builder section
            packBuilderSection
        }
        .frame(width: 500, height: 540)
        .alert("Pack Installed!", isPresented: $showSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your new sound pack '\(packName)' has been installed. Select it in Settings → TTS → Custom Pack.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "speaker.wave.2.bubble.left")
                    .foregroundColor(.accentBlue)
                Text("Sound Pack Installer")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Text("Sounds may be copyrighted. For personal use only.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sounds...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performSearch() }
                Button("Search") { performSearch() }
                    .buttonStyle(.bordered)
                    .disabled(store.isSearching)
            }

            // Suggestion chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            searchQuery = suggestion
                            performSearch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.statusRed)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    private var resultsSection: some View {
        Group {
            if store.isSearching {
                VStack {
                    ProgressView()
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if store.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Search for game sounds above")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.searchResults) { result in
                            SoundResultRow(
                                result: result,
                                store: store,
                                ttsEngine: ttsEngine
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 160, maxHeight: 200)
            }
        }
    }

    // MARK: - Pack Builder

    private var packBuilderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pack Builder")
                    .font(.callout.bold())
                Spacer()
                if !store.stagedSounds.isEmpty {
                    Button("Clear All") { store.clearStaged() }
                        .buttonStyle(.borderless)
                        .foregroundColor(.statusRed)
                        .controlSize(.small)
                }
            }

            // Pack name
            HStack {
                Text("Name:")
                    .foregroundColor(.secondary)
                TextField("e.g. WarCraft Peon", text: $packName)
                    .textFieldStyle(.roundedBorder)
            }

            if store.stagedSounds.isEmpty {
                Text("Add sounds from search results using + Success / + Error buttons")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                // Two-column layout: success | error
                HStack(alignment: .top, spacing: 16) {
                    // Success column
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Success (\(store.stagedSuccessCount))", systemImage: "checkmark.circle")
                            .font(.caption.bold())
                            .foregroundColor(.statusGreen)

                        ForEach(store.stagedSounds.filter { $0.category == .success }) { staged in
                            StagedSoundRow(staged: staged, store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Error column
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Error (\(store.stagedErrorCount))", systemImage: "xmark.circle")
                            .font(.caption.bold())
                            .foregroundColor(.statusRed)

                        ForEach(store.stagedSounds.filter { $0.category == .error }) { staged in
                            StagedSoundRow(staged: staged, store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Install button + progress
            if store.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: store.downloadProgress)
                    Text("Downloading \(Int(store.downloadProgress * 100))%...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: installPack) {
                    Label("Install Pack (\(store.stagedSounds.count) sounds)", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.stagedSounds.isEmpty || packName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func performSearch() {
        Task { await store.search(query: searchQuery) }
    }

    private func installPack() {
        Task {
            do {
                try await store.installPack(name: packName, soundPackManager: soundPackManager)
                showSuccessAlert = true
            } catch {
                store.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Sound Result Row

private struct SoundResultRow: View {
    let result: SoundSearchResult
    @ObservedObject var store: SoundPackStore
    let ttsEngine: TTSEngine

    @State private var isPreviewing = false
    @State private var duration: String?

    var body: some View {
        HStack(spacing: 8) {
            // Preview button
            Button(action: previewSound) {
                Image(systemName: isPreviewing ? "speaker.wave.3" : "play.circle")
                    .foregroundColor(.accentBlue)
            }
            .buttonStyle(.borderless)
            .disabled(isPreviewing)

            // Title
            Text(result.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            // Duration (appears after preview)
            if let duration {
                Text(duration)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Stage buttons
            Button("+ Success") {
                store.addToStaged(result, category: .success)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.statusGreen)

            Button("+ Error") {
                store.addToStaged(result, category: .error)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.statusRed)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func previewSound() {
        isPreviewing = true
        Task {
            let localURL = await store.preview(result, using: ttsEngine)
            // Show duration if we got a local file
            if let localURL, let secs = SoundPackStore.audioDuration(at: localURL) {
                duration = SoundPackStore.formatDuration(secs)
            }
            // Brief delay so the icon animation is visible
            try? await Task.sleep(for: .seconds(0.5))
            isPreviewing = false
        }
    }
}

// MARK: - Staged Sound Row

private struct StagedSoundRow: View {
    let staged: StagedSound
    @ObservedObject var store: SoundPackStore

    var body: some View {
        HStack(spacing: 4) {
            Text(staged.result.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(action: { store.removeFromStaged(staged) }) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}
