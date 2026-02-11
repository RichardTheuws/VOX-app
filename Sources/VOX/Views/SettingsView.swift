import SwiftUI

/// Settings window with tabbed interface.
struct SettingsView: View {
    @ObservedObject var settings: VoxSettings
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }

            AppsSettingsTab(settings: settings)
                .tabItem { Label("Apps", systemImage: "app.badge") }

            TTSSettingsTab(settings: settings)
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
