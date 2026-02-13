import Foundation
import AppKit

/// Sound packs for the Notice verbosity level.
/// Built-in packs use TTS-spoken phrases; users can also add custom audio packs.
enum NoticeSoundPack: String, CaseIterable, Codable, Identifiable {
    case tts = "TTS"
    case warcraft = "WarCraft Peon"
    case mario = "Super Mario"
    case commandConquer = "Command & Conquer"
    case zelda = "Legend of Zelda"
    case systemSounds = "macOS Sounds"

    var id: String { rawValue }
    var label: String { rawValue }

    var description: String {
        switch self {
        case .tts:             return "Spoken notice in your language"
        case .warcraft:        return "\"Job's done!\", \"Work complete.\""
        case .mario:           return "\"Let's-a go!\", \"Wahoo!\""
        case .commandConquer:  return "\"Construction complete.\", \"Unit ready.\""
        case .zelda:           return "\"Quest complete!\", \"Item acquired!\""
        case .systemSounds:    return "macOS built-in notification sounds"
        }
    }

    // MARK: - TTS Phrases (built-in game packs)

    var successPhrases: [String] {
        switch self {
        case .tts:             return []
        case .warcraft:        return ["Job's done!", "Work complete.", "Ready to work!", "Something need doing?", "Okie dokie."]
        case .mario:           return ["Let's-a go!", "Here we go!", "Wahoo!", "Okey dokey!", "Yahoo!"]
        case .commandConquer:  return ["Construction complete.", "Unit ready.", "Building.", "Acknowledged.", "New construction options."]
        case .zelda:           return ["Quest complete!", "Item acquired!", "Secret discovered!", "You got it!"]
        case .systemSounds:    return []
        }
    }

    var errorPhrases: [String] {
        switch self {
        case .tts:             return []
        case .warcraft:        return ["More work?", "Stop poking me!", "Me not that kind of orc!", "What you want?"]
        case .mario:           return ["Mamma mia!", "Oh no!", "Let's-a try again."]
        case .commandConquer:  return ["Cannot deploy here.", "Insufficient funds.", "Unable to comply.", "Low power."]
        case .zelda:           return ["Watch out!", "Hey! Listen!", "You need more hearts!"]
        case .systemSounds:    return []
        }
    }

    /// Pick a random phrase for the given outcome.
    func randomPhrase(isSuccess: Bool) -> String? {
        let phrases = isSuccess ? successPhrases : errorPhrases
        return phrases.randomElement()
    }

    // MARK: - System Sound Names

    static let successSounds = ["Glass", "Hero", "Ping", "Pop", "Purr"]
    static let errorSounds = ["Basso", "Funk", "Sosumi", "Bottle"]
}

// MARK: - Custom Sound Pack (filesystem-based)

/// Represents a user-provided sound pack from ~/Library/Application Support/VOX/SoundPacks/
struct CustomSoundPack: Identifiable {
    let name: String        // Directory name
    let path: URL           // Full path to pack directory
    var successFiles: [URL] // Audio files in success/
    var errorFiles: [URL]   // Audio files in error/

    var id: String { name }

    func randomSound(isSuccess: Bool) -> URL? {
        let files = isSuccess ? successFiles : errorFiles
        return files.randomElement()
    }
}

// MARK: - Sound Pack Manager

/// Manages discovery and loading of custom sound packs from the filesystem.
final class SoundPackManager: ObservableObject {
    @Published var customPacks: [CustomSoundPack] = []

    static let supportedExtensions: Set<String> = ["wav", "mp3", "aif", "aiff", "m4a", "caf"]

    /// Base directory for custom sound packs.
    static var soundPacksDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VOX/SoundPacks")
    }

    /// Scan the SoundPacks directory for user-provided packs.
    func scanForPacks() {
        let dir = Self.soundPacksDirectory
        let fm = FileManager.default

        // Create directory if it doesn't exist
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            customPacks = []
            return
        }

        customPacks = contents.compactMap { packURL in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: packURL.path, isDirectory: &isDir), isDir.boolValue else { return nil }

            let successDir = packURL.appendingPathComponent("success")
            let errorDir = packURL.appendingPathComponent("error")

            let successFiles = audioFiles(in: successDir)
            let errorFiles = audioFiles(in: errorDir)

            // Only include packs that have at least one sound file
            guard !successFiles.isEmpty || !errorFiles.isEmpty else { return nil }

            return CustomSoundPack(
                name: packURL.lastPathComponent,
                path: packURL,
                successFiles: successFiles,
                errorFiles: errorFiles
            )
        }
    }

    /// Look up a custom pack by name.
    func selectedPack(named name: String) -> CustomSoundPack? {
        customPacks.first { $0.name == name }
    }

    /// Create the template directory structure for a new custom pack.
    func createPackTemplate(name: String) throws {
        let packDir = Self.soundPacksDirectory.appendingPathComponent(name)
        let fm = FileManager.default
        try fm.createDirectory(at: packDir.appendingPathComponent("success"), withIntermediateDirectories: true)
        try fm.createDirectory(at: packDir.appendingPathComponent("error"), withIntermediateDirectories: true)
    }

    private func audioFiles(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
    }
}

// MARK: - Unified Sound Pack Choice

/// Unified type for both built-in and custom sound packs.
/// Used in Pickers so a single dropdown can show all available packs.
enum SoundPackChoice: Hashable {
    case builtIn(NoticeSoundPack)
    case custom(String)  // pack name

    var label: String {
        switch self {
        case .builtIn(let pack): return pack.label
        case .custom(let name): return name
        }
    }
}
