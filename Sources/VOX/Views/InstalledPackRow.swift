import SwiftUI
import AVFoundation

/// Row view for an installed custom sound pack in the TTS settings.
/// Shows pack name, sound count, expandable list of sounds with play/delete.
struct InstalledPackRow: View {
    let pack: CustomSoundPack
    @ObservedObject var soundPackManager: SoundPackManager
    let ttsEngine: TTSEngine

    @State private var showDeleteConfirmation = false

    var body: some View {
        DisclosureGroup {
            // Success sounds
            if !pack.successFiles.isEmpty {
                Label("Success (\(pack.successFiles.count))", systemImage: "checkmark.circle")
                    .font(.caption.bold())
                    .foregroundColor(.statusGreen)
                ForEach(pack.successFiles, id: \.absoluteString) { url in
                    SoundFileRow(url: url, ttsEngine: ttsEngine) {
                        try? soundPackManager.deleteSound(at: url, fromPack: pack.name)
                    }
                }
            }

            // Error sounds
            if !pack.errorFiles.isEmpty {
                Label("Error (\(pack.errorFiles.count))", systemImage: "xmark.circle")
                    .font(.caption.bold())
                    .foregroundColor(.statusRed)
                ForEach(pack.errorFiles, id: \.absoluteString) { url in
                    SoundFileRow(url: url, ttsEngine: ttsEngine) {
                        try? soundPackManager.deleteSound(at: url, fromPack: pack.name)
                    }
                }
            }

            // Delete pack button
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Pack", systemImage: "trash")
            }
            .confirmationDialog(
                "Delete '\(pack.name)'?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    try? soundPackManager.deletePack(named: pack.name)
                }
            } message: {
                Text("This will permanently remove the sound pack and all its audio files.")
            }
        } label: {
            HStack {
                Text(pack.name).font(.callout)
                Spacer()
                Text("\(pack.successFiles.count + pack.errorFiles.count) sounds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Individual sound file row with play, duration, and delete controls.
struct SoundFileRow: View {
    let url: URL
    let ttsEngine: TTSEngine
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                ttsEngine.playCustomSound(at: url)
            } label: {
                Image(systemName: "play.circle")
                    .foregroundColor(.accentBlue)
            }
            .buttonStyle(.borderless)

            Text(url.deletingPathExtension().lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Duration
            if let duration = SoundPackStore.audioDuration(at: url) {
                Text(SoundPackStore.formatDuration(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, 16)
    }
}
