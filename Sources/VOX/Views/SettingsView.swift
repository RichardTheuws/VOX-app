import SwiftUI

/// Settings window with tabbed interface.
struct SettingsView: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }

            VoiceSettingsTab(settings: settings, appState: appState)
                .tabItem { Label("Voice", systemImage: "mic") }

            AppsSettingsTab(settings: settings)
                .tabItem { Label("Apps", systemImage: "app.badge") }

            TTSSettingsTab(settings: settings)
                .tabItem { Label("TTS", systemImage: "speaker.wave.2") }

            AdvancedSettingsTab(settings: settings)
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

            Section("Keyboard Shortcuts") {
                HStack {
                    Text("Push-to-talk")
                    Spacer()
                    Text("⌥Space")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Cycle verbosity")
                    Spacer()
                    Text("⌥V")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Cancel command")
                    Spacer()
                    Text("Escape")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
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

// MARK: - Voice Tab

struct VoiceSettingsTab: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Speech-to-Text Engine") {
                Picker("Engine", selection: $settings.sttEngine) {
                    ForEach(STTEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }

                if settings.sttEngine == .hex {
                    HStack {
                        Text("Hex Status")
                        Spacer()
                        Circle()
                            .fill(appState.hexBridge.isHexRunning ? Color.statusGreen : Color.statusRed)
                            .frame(width: 8, height: 8)
                        Text(appState.hexBridge.isHexRunning ? "Connected" : "Not running")
                            .foregroundColor(.secondary)
                    }

                    if !appState.hexBridge.isHexRunning {
                        Button("Launch Hex") {
                            appState.hexBridge.launchHex()
                        }
                    }
                }
            }

            Section("Activation Mode") {
                Picker("Mode", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
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

    var body: some View {
        Form {
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
                }
            }

            Section("Routing") {
                Picker("Default target", selection: $settings.defaultTarget) {
                    ForEach(TargetApp.allCases) { app in
                        Text(app.rawValue).tag(app)
                    }
                }
                Picker("Fallback target", selection: $settings.fallbackTarget) {
                    ForEach(TargetApp.allCases) { app in
                        Text(app.rawValue).tag(app)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
}

// MARK: - TTS Tab

struct TTSSettingsTab: View {
    @ObservedObject var settings: VoxSettings

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
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @ObservedObject var settings: VoxSettings

    var body: some View {
        Form {
            Section("Summary Engine") {
                Picker("Method", selection: $settings.summarizationMethod) {
                    ForEach(SummarizationMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }

                if settings.summarizationMethod == .ollama {
                    TextField("Ollama URL", text: $settings.ollamaURL)
                    TextField("Model", text: $settings.ollamaModel)
                }
            }

            Section("Terminal") {
                HStack {
                    Text("Command timeout")
                    Slider(value: $settings.commandTimeout, in: 5...120, step: 5)
                    Text("\(Int(settings.commandTimeout))s")
                        .frame(width: 40)
                        .foregroundColor(.secondary)
                }
            }

            Section("Safety") {
                Toggle("Confirm destructive commands", isOn: $settings.confirmDestructive)
            }

            Section("Logging") {
                Toggle("Log commands to file", isOn: $settings.logToFile)
            }

            Section("Data") {
                Button("Reset to Defaults") {
                    // Reset all UserDefaults for the app
                    if let bundleID = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleID)
                    }
                }
                .foregroundColor(.statusRed)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
