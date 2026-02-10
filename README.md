# VOX — Voice-Operated eXecution

> Talk to your terminal. Hear what matters.

VOX is an open-source macOS menu bar app that lets developers control their terminal and IDEs with voice commands, and hear configurable audio summaries of responses.

## Features

- **Push-to-talk** — Hold Option+Space to dictate commands
- **Terminal execution** — Voice commands run directly in your shell
- **Smart summaries** — 4 verbosity levels: Silent, Ping, Summary, Full
- **Hex integration** — On-device speech-to-text via [Hex](https://github.com/kitlangton/Hex)
- **Safety first** — Destructive command detection with voice confirmation
- **Command history** — Searchable log of all voice commands and results
- **Floating HUD** — Push-to-talk overlay and confirm dialogs as centered floating panels
- **Privacy-first** — All processing on-device, no telemetry, no cloud required

## Requirements

- macOS 14.0 (Sonoma) or later
- [Hex](https://hex.kitlangton.com/) for speech-to-text (recommended)
- Xcode 16+ / Swift 6 (for building from source)

## Install as macOS App

```bash
# Clone the repository
git clone https://github.com/RichardTheuws/VOX-app.git
cd VOX-app

# Build and install to /Applications
./scripts/build-app.sh --install

# Or build, install, and launch immediately
./scripts/build-app.sh --install --open
```

After installation, VOX appears in Spotlight search and can be launched like any Mac app.

## Build from Source

```bash
# Build from command line
swift build

# Run directly
.build/debug/VOX

# Or build release
swift build -c release
.build/release/VOX

# Build .app bundle (without installing)
./scripts/build-app.sh
# Output: build/VOX.app
```

## Run Tests

```bash
swift test
# 90 tests, 0 failures
```

## Usage

1. Launch VOX — it appears as an icon in your menu bar
2. Complete the onboarding wizard (first launch only)
3. Press **Option+Space** to start push-to-talk
4. Speak your command (e.g., "git status", "list files", "claude explain this code")
5. VOX executes the command and speaks the summary
6. Press **Escape** to cancel any action

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Option+Space | Push-to-talk (hold) |
| Option+V | Cycle verbosity level |
| Escape | Cancel current action |

### Voice Prefixes

| Prefix | Target |
|--------|--------|
| "terminal ..." | Terminal.app |
| "claude ..." | Claude Code CLI |
| "code ..." | VS Code / Cursor |

### Natural Language Commands

| Say | Executes |
|-----|----------|
| "list files" / "show files" | `ls -la` |
| "where am I" / "show directory" | `pwd` |
| "go to Documents" | `cd Documents` |
| "create folder my-project" | `mkdir -p my-project` |

## Verbosity Levels

| Level | Name | What you hear |
|-------|------|---------------|
| 0 | Silent | Nothing (visual indicator only) |
| 1 | Ping | "Done." or "Error occurred." |
| 2 | Summary | Heuristic 1-2 sentence summary (default) |
| 3 | Full | Complete response read aloud |

## Architecture

```
VOX (Menu Bar App)
├── Models/         — VerbosityLevel, TargetApp, VoxCommand, VoxSettings, VOXVersion
├── Services/       — HexBridge, TerminalExecutor, ResponseProcessor, TTSEngine,
│                     HotkeyManager, CommandRouter, CommandHistory, SafetyChecker
├── Views/          — MenuBarView, PushToTalkOverlay, SettingsView, HistoryView,
│                     OnboardingView, DestructiveConfirmView
├── AppState.swift  — Central coordinator + floating panel management
└── VOXApp.swift    — @main entry point with MenuBarExtra
```

## Roadmap

- **v0.1** — Terminal + Claude Code CLI + macOS Say TTS + 90 tests
- **v0.3** — App icon + .app bundle + onboarding wizard + accessibility check *(current)*
- **v0.4** — Kokoro/Piper/ElevenLabs TTS + VS Code/Cursor/Windsurf
- **v0.4** — Plugin system + Git/Docker voice commands
- **v1.0** — Production ready + Homebrew install

## Tech Stack

- **Language**: Swift 6 / SwiftUI
- **STT**: Hex (WhisperKit/Parakeet, on-device)
- **TTS**: macOS NSSpeechSynthesizer (MVP), Kokoro/Piper/ElevenLabs (planned)
- **Platform**: macOS 14+ (Apple Silicon optimized)
- **Testing**: XCTest (90 unit + integration tests)

## Contributing

Contributions are welcome! Please open an issue or pull request.

## License

MIT License — see [LICENSE](LICENSE)

## Brand

Part of the [tools.theuws.com](https://tools.theuws.com) ecosystem.

---
Version 0.3.0
