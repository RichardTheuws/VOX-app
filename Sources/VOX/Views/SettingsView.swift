import SwiftUI

/// Settings window with tabbed interface.
struct SettingsView: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }

            AppsSettingsTab(settings: settings, soundPackManager: appState.soundPackManager)
                .tabItem { Label("Apps", systemImage: "app.badge") }

            TTSSettingsTab(settings: settings, soundPackManager: appState.soundPackManager, soundPackStore: appState.soundPackStore, ttsEngine: appState.ttsEngine)
                .tabItem { Label("TTS", systemImage: "speaker.wave.2") }

            AdvancedSettingsTab(settings: settings, ollamaService: appState.ollamaService)
                .tabItem { Label("Advanced", systemImage: "wrench") }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings: VoxSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
            }

            Section("Monitoring") {
                Toggle("Monitor keyboard input", isOn: $settings.monitorKeyboardInput)
                Text("When enabled, VOX also monitors app output for keyboard interactions — not just Hex voice commands. Requires restart.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Language") {
                Picker("Input language", selection: $settings.inputLanguage) {
                    ForEach(InputLanguage.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                Picker("Response language", selection: $settings.responseLanguage) {
                    ForEach(ResponseLanguage.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Apps Tab

struct AppsSettingsTab: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var soundPackManager: SoundPackManager

    @State private var isAccessibilityGranted = AccessibilityReader.isAccessibilityGranted()
    @State private var permissionCheckTimer: Timer?
    @State private var showRestartHint = false

    var body: some View {
        Form {
            Section("Permissions") {
                HStack {
                    Circle()
                        .fill(isAccessibilityGranted ? Color.statusGreen : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Accessibility")
                    Spacer()
                    if isAccessibilityGranted {
                        Text("Granted")
                            .font(.caption)
                            .foregroundColor(.statusGreen)
                    } else {
                        Button("Grant Permission") {
                            AccessibilityReader.requestAccessibilityPermission()
                            // Poll every 2 seconds for up to 30 seconds after granting
                            startPermissionPolling()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Refresh") {
                            isAccessibilityGranted = AccessibilityReader.isAccessibilityGranted()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                if !isAccessibilityGranted {
                    Text("Required to monitor Cursor, VS Code, Windsurf and Claude Desktop. Not needed for Terminal or iTerm2.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if showRestartHint && !isAccessibilityGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Permission granted in System Settings? Restart VOX to activate.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Section("Target Apps") {
                Toggle("Auto-detect active app", isOn: $settings.autoDetectTarget)

                ForEach(TargetApp.allCases) { app in
                    HStack {
                        Circle()
                            .fill(isAppInstalled(app) ? Color.statusGreen : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(app.rawValue)
                        Spacer()
                        Text(app.tier.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: verbosityBinding(for: app)) {
                            ForEach(VerbosityLevel.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .frame(width: 120)
                    }
                    if !app.isTerminalBased && isAppInstalled(app) && !isAccessibilityGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Requires Accessibility permission")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.leading, 16)
                    }

                    // Sound pack picker — only visible when verbosity is Notice
                    if settings.verbosity(for: app) == .notice {
                        HStack {
                            Image(systemName: "speaker.wave.1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Sound Pack", selection: soundPackChoiceBinding(for: app)) {
                                // Built-in packs
                                ForEach(NoticeSoundPack.allCases) { pack in
                                    Text(pack.label).tag(SoundPackChoice.builtIn(pack))
                                }
                                // Custom packs (if any exist)
                                if !soundPackManager.customPacks.isEmpty {
                                    Divider()
                                    ForEach(soundPackManager.customPacks) { pack in
                                        Text("\(pack.name) (\(pack.successFiles.count + pack.errorFiles.count) sounds)")
                                            .tag(SoundPackChoice.custom(pack.name))
                                    }
                                }
                            }
                            .frame(width: 220)
                        }
                        .padding(.leading, 16)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // Always check fresh — never rely on cached permission state
            isAccessibilityGranted = AccessibilityReader.isAccessibilityGranted()
        }
        .onDisappear {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    /// Poll AXIsProcessTrusted() every 2s after the user clicks "Grant Permission".
    /// macOS may not reflect the change immediately — and sometimes requires an app restart.
    private func startPermissionPolling() {
        permissionCheckTimer?.invalidate()
        var attempts = 0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            attempts += 1
            let granted = AccessibilityReader.isAccessibilityGranted()
            DispatchQueue.main.async {
                isAccessibilityGranted = granted
                if granted {
                    timer.invalidate()
                    permissionCheckTimer = nil
                    showRestartHint = false
                } else if attempts >= 5 {
                    // After 10 seconds, show restart hint — macOS often requires it
                    showRestartHint = true
                    timer.invalidate()
                    permissionCheckTimer = nil
                }
            }
        }
    }

    private func isAppInstalled(_ app: TargetApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) != nil
    }

    private func verbosityBinding(for app: TargetApp) -> Binding<VerbosityLevel> {
        Binding(
            get: { settings.verbosity(for: app) },
            set: { settings.setVerbosity($0, for: app) }
        )
    }

    private func soundPackChoiceBinding(for app: TargetApp) -> Binding<SoundPackChoice> {
        Binding(
            get: {
                let customName = settings.customSoundPackName(for: app)
                if !customName.isEmpty,
                   soundPackManager.customPacks.contains(where: { $0.name == customName }) {
                    return .custom(customName)
                }
                return .builtIn(settings.soundPack(for: app))
            },
            set: { choice in
                switch choice {
                case .builtIn(let pack):
                    settings.setSoundPack(pack, for: app)
                    settings.setCustomSoundPackName("", for: app)  // Clear custom
                case .custom(let name):
                    settings.setCustomSoundPackName(name, for: app)
                }
            }
        )
    }
}

// MARK: - TTS Tab

struct TTSSettingsTab: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var soundPackManager: SoundPackManager
    @ObservedObject var soundPackStore: SoundPackStore
    let ttsEngine: TTSEngine

    @State private var showInstaller = false
    @State private var edgeTTSInstalled = TTSEngine.isEdgeTTSInstalled

    var body: some View {
        Form {
            Section("Text-to-Speech Engine") {
                Picker("Engine", selection: $settings.ttsEngine) {
                    ForEach(TTSEngineType.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }

                HStack {
                    Text("Speed")
                    Slider(value: $settings.ttsSpeed, in: 0.5...2.0, step: 0.1)
                    Text(String(format: "%.1fx", settings.ttsSpeed))
                        .frame(width: 40)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Volume")
                    Slider(value: $settings.ttsVolume, in: 0.0...1.0, step: 0.05)
                    Text("\(Int(settings.ttsVolume * 100))%")
                        .frame(width: 40)
                        .foregroundColor(.secondary)
                }

                Toggle("Interrupt on new command", isOn: $settings.interruptOnNewCommand)
            }

            Section("Voice") {
                Picker("Voice type", selection: $settings.voiceGender) {
                    ForEach(VoiceGender.allCases, id: \.self) { gender in
                        Text(gender.rawValue).tag(gender)
                    }
                }
                Text("VOX detects the language automatically and picks a matching voice.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Engine-specific configuration
            if settings.ttsEngine == .elevenLabs {
                Section("ElevenLabs") {
                    SecureField("API Key", text: $settings.elevenLabsAPIKey)
                    TextField("Voice ID (optional)", text: $settings.elevenLabsVoiceID)
                    Text("Default: Rachel (multilingual). Browse voices at elevenlabs.io")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if settings.ttsEngine == .edgeTTS {
                Section("Edge TTS") {
                    if !edgeTTSInstalled {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("edge-tts not found. Install via: pip3 install edge-tts")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.statusGreen)
                            Text("edge-tts installed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Notice Sound Pack") {
                Picker("Sound Pack", selection: globalSoundPackChoiceBinding) {
                    // Built-in packs
                    ForEach(NoticeSoundPack.allCases) { pack in
                        Text(pack.label).tag(SoundPackChoice.builtIn(pack))
                    }
                    // Custom packs (if any exist)
                    if !soundPackManager.customPacks.isEmpty {
                        Divider()
                        ForEach(soundPackManager.customPacks) { pack in
                            Text("\(pack.name) (\(pack.successFiles.count + pack.errorFiles.count) sounds)")
                                .tag(SoundPackChoice.custom(pack.name))
                        }
                    }
                }

                // Description for built-in packs
                if settings.customSoundPackName.isEmpty {
                    Text(settings.noticeSoundPack.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Preview") {
                    previewCurrentPack()
                }
                .buttonStyle(.bordered)

                Button("Browse & Install Sounds…") {
                    showInstaller = true
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showInstaller) {
                    SoundPackInstallerView(
                        store: soundPackStore,
                        soundPackManager: soundPackManager,
                        ttsEngine: ttsEngine
                    )
                }

                DisclosureGroup("Add your own sound packs") {
                    Text("Place audio files (.wav, .mp3, .aif) in:")
                        .font(.caption)
                    Text("~/Library/Application Support/VOX/SoundPacks/[Pack Name]/success/")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("~/Library/Application Support/VOX/SoundPacks/[Pack Name]/error/")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack {
                        Button("Open Folder") {
                            // Ensure directory exists before opening
                            try? FileManager.default.createDirectory(
                                at: SoundPackManager.soundPacksDirectory,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(SoundPackManager.soundPacksDirectory)
                        }
                        Button("Refresh") {
                            soundPackManager.scanForPacks()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Installed Sound Packs") {
                if soundPackManager.customPacks.isEmpty {
                    Text("No custom sound packs installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(soundPackManager.customPacks) { pack in
                        InstalledPackRow(
                            pack: pack,
                            soundPackManager: soundPackManager,
                            ttsEngine: ttsEngine
                        )
                    }
                }
            }

            Section("Default Verbosity") {
                Picker("Global default", selection: $settings.defaultVerbosity) {
                    ForEach(VerbosityLevel.allCases) { level in
                        Text("\(level.label) — \(level.description)").tag(level)
                    }
                }

                Toggle("Error escalation", isOn: $settings.errorEscalation)

                if settings.errorEscalation {
                    Picker("Error verbosity", selection: $settings.errorVerbosity) {
                        ForEach(VerbosityLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var globalSoundPackChoiceBinding: Binding<SoundPackChoice> {
        Binding(
            get: {
                if !settings.customSoundPackName.isEmpty,
                   soundPackManager.customPacks.contains(where: { $0.name == settings.customSoundPackName }) {
                    return .custom(settings.customSoundPackName)
                }
                return .builtIn(settings.noticeSoundPack)
            },
            set: { choice in
                switch choice {
                case .builtIn(let pack):
                    settings.noticeSoundPack = pack
                    settings.customSoundPackName = ""
                case .custom(let name):
                    settings.customSoundPackName = name
                }
            }
        )
    }

    private func previewCurrentPack() {
        // Custom pack takes priority
        if !settings.customSoundPackName.isEmpty,
           let customPack = soundPackManager.selectedPack(named: settings.customSoundPackName),
           let soundURL = customPack.randomSound(isSuccess: true) {
            ttsEngine.playCustomSound(at: soundURL)
            return
        }

        let pack = settings.noticeSoundPack
        switch pack {
        case .tts:
            ttsEngine.speak("Done. Check the terminal to continue.")
        case .warcraft, .mario, .commandConquer, .zelda:
            if let phrase = pack.randomPhrase(isSuccess: true) {
                ttsEngine.speak(phrase)
            }
        case .systemSounds:
            let soundName = NoticeSoundPack.successSounds.randomElement() ?? "Glass"
            ttsEngine.playSystemSound(soundName)
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var ollamaService: OllamaService

    @State private var ollamaError: String?

    var body: some View {
        Form {
            Section("Summary Engine") {
                Picker("Method", selection: $settings.summarizationMethod) {
                    Text("Heuristic").tag(SummarizationMethod.heuristic)
                    Text("Ollama (local AI)").tag(SummarizationMethod.ollama)
                }

                if settings.summarizationMethod == .ollama {
                    // Server status
                    HStack {
                        Circle()
                            .fill(ollamaService.isServerRunning ? Color.statusGreen : Color.statusRed)
                            .frame(width: 8, height: 8)
                        Text(ollamaService.isServerRunning ? "Ollama running" : "Ollama not running")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Check") {
                            Task { await ollamaService.checkServer() }
                        }
                        .buttonStyle(.borderless)
                    }

                    // Installation check
                    if !OllamaService.isOllamaInstalled() {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Ollama not installed")
                            Spacer()
                            Link("Download", destination: OllamaService.downloadURL)
                                .foregroundColor(.accentBlue)
                        }
                    }

                    // Model info
                    if ollamaService.isServerRunning {
                        HStack {
                            Text("Model")
                            Spacer()
                            if ollamaService.availableModels.contains(where: {
                                $0.name.lowercased().hasPrefix(settings.ollamaModel.lowercased())
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.statusGreen)
                                    Text(settings.ollamaModel)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Not installed")
                                    .foregroundColor(.orange)
                            }
                        }

                        // Download model button
                        if !ollamaService.availableModels.contains(where: {
                            $0.name.lowercased().hasPrefix(settings.ollamaModel.lowercased())
                        }) {
                            if ollamaService.isDownloadingModel {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Downloading \(settings.ollamaModel)...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ProgressView(value: ollamaService.downloadProgress)
                                    Text("\(Int(ollamaService.downloadProgress * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Button("Download \(settings.ollamaModel)") {
                                    Task {
                                        do {
                                            try await ollamaService.pullModel(settings.ollamaModel)
                                            ollamaError = nil
                                        } catch {
                                            ollamaError = error.localizedDescription
                                        }
                                    }
                                }
                            }
                        }

                        // Available models list
                        if !ollamaService.availableModels.isEmpty {
                            DisclosureGroup("Installed models (\(ollamaService.availableModels.count))") {
                                ForEach(ollamaService.availableModels) { model in
                                    HStack {
                                        Text(model.name)
                                            .font(.caption)
                                        Spacer()
                                        Text(model.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if let error = ollamaError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.statusRed)
                    }

                    // Advanced Ollama settings
                    DisclosureGroup("Advanced") {
                        TextField("Ollama URL", text: $settings.ollamaURL)
                        TextField("Model name", text: $settings.ollamaModel)
                        Stepper("Max summary sentences: \(settings.maxSummaryLength)", value: $settings.maxSummaryLength, in: 1...5)
                    }
                }
            }

            Section("Terminal Monitoring") {
                HStack {
                    Text("Monitor timeout")
                    Slider(value: $settings.commandTimeout, in: 5...120, step: 5)
                    Text("\(Int(settings.commandTimeout))s")
                        .frame(width: 40)
                        .foregroundColor(.secondary)
                }
            }

            Section("Logging") {
                Toggle("Log commands to file", isOn: $settings.logToFile)
            }

            Section("Data") {
                Button("Reset to Defaults") {
                    if let bundleID = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleID)
                    }
                }
                .foregroundColor(.statusRed)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if settings.summarizationMethod == .ollama {
                Task { await ollamaService.checkServer() }
            }
        }
    }
}
