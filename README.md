# VOX — Voice-Operated eXecution

> Talk to your terminal. Hear what matters.

VOX is an open-source macOS menu bar companion for [Hex](https://hex.kitlangton.com/). When you dictate a command into Terminal or iTerm2 via Hex, VOX monitors the output and reads it back to you with configurable verbosity. Built with Swift 6 and SwiftUI, VOX runs entirely on-device with zero telemetry.

<p align="center">
  <img src="Assets/icon_1024.png" width="128" alt="VOX App Icon" />
</p>

## Why VOX?

Developers using voice-driven tools like [Hex](https://hex.kitlangton.com/) can dictate commands into their terminal — but they still have to read the output. With AI tools producing lengthy responses (Claude Code, Cursor, Windsurf), the bottleneck has shifted from typing to reading.

VOX closes the loop: **dictate your command with Hex, hear the response from VOX**. No more reading 500-word outputs when a 2-sentence summary tells you everything you need.

## How It Works

```
You speak → Hex transcribes → Command runs in Terminal → VOX reads the response
```

1. **Hex** listens to your voice and types the transcription into Terminal/iTerm2
2. **Terminal** executes the command as normal
3. **VOX** detects the new output via AppleScript, processes it, and speaks a summary

VOX never executes commands itself — it only reads terminal output. No accessibility permissions, no shell access, no risk.

## Features

- **Terminal monitoring** — Detects new output in Terminal.app and iTerm2 after Hex dictation
- **Smart summaries** — 4 verbosity levels: Silent, Ping, Summary, Full
- **Hex integration** — Watches Hex's `transcription_history.json` for new dictations with source app context
- **Per-app verbosity** — Configure different verbosity levels per target app
- **TTS output** — Speaks responses via macOS NSSpeechSynthesizer with configurable speed and volume
- **Command history** — Searchable, filterable log of all monitored commands and responses
- **Onboarding wizard** — 3-step setup: Hex, TTS, Voice Test
- **Privacy-first** — All processing on-device, no telemetry, no cloud required

## Requirements

- macOS 14.0 (Sonoma) or later
- [Hex](https://hex.kitlangton.com/) for speech-to-text
- Xcode 16+ / Swift 6 (for building from source)

No accessibility or microphone permissions needed — Hex handles all voice input.

## Quick Start

### Install as macOS App

```bash
# Clone the repository
git clone https://github.com/RichardTheuws/VOX-app.git
cd VOX-app

# Build and install to /Applications
./scripts/build-app.sh --install

# Or build, install, and launch immediately
./scripts/build-app.sh --install --open
```

After installation, VOX appears in Spotlight search and can be launched like any macOS app. It lives in your menu bar.

### Build from Source

```bash
# Debug build
swift build

# Run directly
.build/debug/VOX

# Release build (optimized)
swift build -c release
.build/release/VOX

# Build .app bundle only (no install)
./scripts/build-app.sh
# Output: build/VOX.app
```

### Run Tests

```bash
swift test
# 32 tests, 0 failures
```

## Getting Started

1. **Launch VOX** — it appears as an ear icon in your menu bar
2. **Complete onboarding** — the 3-step wizard guides you through:
   - Installing and starting [Hex](https://hex.kitlangton.com/)
   - Selecting a TTS engine and voice
   - Testing the full flow: dictate in Terminal, hear VOX respond
3. **Open Terminal** and start dictating commands with Hex
4. **VOX automatically** monitors the output and speaks a summary

## Verbosity Levels

Configure per-app in Settings or set a global default:

| Level | Name | What you hear |
|-------|------|---------------|
| 0 | **Silent** | Nothing (visual indicator only) |
| 1 | **Ping** | "Done." or "Error occurred." |
| 2 | **Summary** *(default)* | Heuristic 1-2 sentence summary |
| 3 | **Full** | Complete response read aloud |

The Summary level uses smart heuristics to extract what matters:
- Git status: file counts, branch name, clean/dirty state
- Build output: success/failure, error messages
- General output: first meaningful line + error detection
- Error escalation: automatically increases verbosity on errors

## Architecture

```
VOX (Menu Bar App)
├── Models/
│   ├── VerbosityLevel.swift    — 4-level verbosity enum with cycling
│   ├── TargetApp.swift         — Terminal, iTerm2, Claude Code, VS Code, etc.
│   ├── VoxCommand.swift        — Command history model with Codable
│   ├── VoxSettings.swift       — @AppStorage settings
│   └── VOXVersion.swift        — Centralized version constant
├── Services/
│   ├── HexBridge.swift         — Monitors Hex transcription_history.json
│   ├── TerminalReader.swift    — Reads terminal content via AppleScript
│   ├── ResponseProcessor.swift — Verbosity-aware output summarization
│   ├── TTSEngine.swift         — Text-to-speech via NSSpeechSynthesizer
│   └── CommandHistory.swift    — Persistent command log (JSON)
├── Views/
│   ├── MenuBarView.swift       — Menu bar dropdown with status + actions
│   ├── SettingsView.swift      — 4-tab settings window
│   ├── HistoryView.swift       — Searchable command history
│   └── OnboardingView.swift    — 3-step first-run wizard
├── AppState.swift              — Central coordinator (Hex → Monitor → TTS)
└── VOXApp.swift                — @main entry point with MenuBarExtra
```

### Key Design Decisions

- **Menu bar-only app** — Uses `NSApp.setActivationPolicy(.accessory)` to live in the menu bar without a dock icon
- **Pure companion** — VOX never executes commands. It only reads terminal output and speaks it. This eliminates the need for accessibility permissions, shell access, and safety checks.
- **AppleScript terminal reading** — Reads terminal content via `osascript` calling `tell application "Terminal"`. Polls for output stabilization before processing.
- **Hex file monitoring** — Watches `transcription_history.json` for new entries with `sourceAppBundleID` to determine if the dictation went to a terminal app
- **Reactive state with Combine** — `AppState` uses `@Published` properties for reactive UI updates

## Hex Integration

VOX uses [Hex](https://hex.kitlangton.com/) for on-device speech-to-text:

1. **Install Hex** from [hex.kitlangton.com](https://hex.kitlangton.com/)
2. **Start Hex** — it runs in your menu bar alongside VOX
3. **Speak** — Hex transcribes your voice and types it into the active app
4. **VOX detects** the transcription via Hex's history file and monitors terminal output

No audio data ever leaves your Mac. Hex supports multiple model sizes with different accuracy/speed tradeoffs.

## Settings

VOX offers a 4-tab settings window:

- **General** — Launch at login, theme (dark/light/system), language preferences
- **Apps** — Per-app verbosity levels, auto-detect target
- **TTS** — Engine selection, speed, volume, interrupt behavior, default verbosity
- **Advanced** — Summarization method, Ollama integration, monitor timeout, logging

## Roadmap

| Version | Milestone | Status |
|---------|-----------|--------|
| v0.1 | Terminal + Claude Code CLI + macOS Say TTS + 90 tests | Done |
| v0.2 | Floating panels + destructive confirm + menu bar improvements | Done |
| v0.3 | App icon + .app bundle + onboarding wizard | Done |
| v0.4 | Hex file monitoring + auto-process transcriptions | Done |
| v0.5 | Monitor mode — read terminal output instead of executing | Done |
| v0.6 | Strip to Hex companion — remove push-to-talk, execution, safety | **Current** |
| v0.7 | Kokoro/Piper TTS + improved summaries | Planned |
| v1.0 | Production ready + Homebrew install | Planned |

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 6 / SwiftUI |
| STT | [Hex](https://hex.kitlangton.com/) (WhisperKit/Parakeet, on-device) |
| TTS | macOS NSSpeechSynthesizer (MVP); Kokoro, Piper (planned) |
| Terminal Reading | AppleScript via `/usr/bin/osascript` |
| Platform | macOS 14+ (Apple Silicon optimized) |
| Testing | XCTest — 32 unit tests |
| Build | Swift Package Manager |

## Privacy & Security

- **No cloud required** — All processing happens on your Mac
- **No telemetry** — Zero analytics, zero tracking, zero data collection
- **No audio storage** — Voice audio is never saved; only transcriptions are logged (optionally)
- **No shell access** — VOX reads terminal output via AppleScript, never executes commands
- **No permissions needed** — No accessibility, no microphone (Hex handles voice input)
- **Open source** — Full source code is public and auditable

## Contributing

Contributions are welcome! Please open an issue or pull request.

### Development Setup

```bash
git clone https://github.com/RichardTheuws/VOX-app.git
cd VOX-app
swift build
swift test  # 32 tests should pass
```

## License

MIT License — see [LICENSE](LICENSE)

## Brand

Part of the [tools.theuws.com](https://tools.theuws.com) ecosystem.

---
Version 0.6.2
