# VOX — Voice-Operated eXecution

> Talk to your terminal. Hear what matters.

VOX is an open-source macOS menu bar app that lets developers control their terminal and IDEs with voice commands, and hear configurable audio summaries of responses. Built with Swift 6 and SwiftUI, VOX runs entirely on-device with zero telemetry.

<p align="center">
  <img src="Assets/icon_1024.png" width="128" alt="VOX App Icon" />
</p>

## Why VOX?

Developers spend hours typing terminal commands, navigating IDEs, and reading lengthy LLM outputs. With AI-powered tools like Claude Code, Cursor, and Windsurf, the bottleneck has shifted from writing code to entering commands and processing output.

VOX changes this: **speak your command, hear what matters**. No more reading 500-word LLM responses when a 2-sentence summary tells you everything you need.

## Features

- **Push-to-talk** — Hold a configurable hotkey to dictate commands (Control+Space, Option+Space, Command+Shift+V, or Fn+Space)
- **CGEventTap hotkeys** — Key events are consumed at the OS level, preventing characters from leaking into apps
- **Terminal execution** — Voice commands run directly in your shell via `/bin/zsh`
- **Claude Code integration** — Route prompts to Claude Code CLI with voice prefix "claude ..."
- **Smart summaries** — 4 verbosity levels: Silent, Ping, Summary, Full
- **Hex integration** — On-device speech-to-text via [Hex](https://hex.kitlangton.com/) (WhisperKit/Parakeet)
- **Safety first** — Destructive command detection (`rm -rf`, `sudo`, `DROP TABLE`, etc.) with voice/click confirmation
- **Command history** — Searchable, filterable log of all voice commands and results
- **Floating HUD** — Push-to-talk overlay and destructive confirm dialogs as centered floating panels
- **Onboarding wizard** — 6-step setup: Accessibility, Microphone, Hex, Hotkey, TTS, Voice Test
- **Natural language** — Say "list files" instead of typing `ls -la`
- **Privacy-first** — All processing on-device, no telemetry, no cloud required

## Requirements

- macOS 14.0 (Sonoma) or later
- [Hex](https://hex.kitlangton.com/) for speech-to-text (recommended)
- Accessibility permission (for global hotkeys via CGEventTap)
- Microphone permission (for voice input via Hex)
- Xcode 16+ / Swift 6 (for building from source)

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
# 90 tests, 0 failures
```

## Getting Started

1. **Launch VOX** — it appears as a microphone icon in your menu bar
2. **Complete onboarding** — the 6-step wizard guides you through:
   - Granting Accessibility access (for global hotkeys)
   - Granting Microphone access (for voice input)
   - Installing and starting [Hex](https://hex.kitlangton.com/) (speech-to-text)
   - Choosing your push-to-talk hotkey
   - Selecting a TTS engine
   - Testing your voice setup with an interactive voice test
3. **Hold your hotkey** (default: Control+Space) and speak a command
4. **Release** to execute — VOX speaks the summary back to you
5. **Press Escape** to cancel any action at any time

## Keyboard Shortcuts

VOX uses CGEventTap for global hotkey interception. Events are consumed at the OS level so they don't leak into other applications.

| Shortcut | Action |
|----------|--------|
| Control+Space *(default)* | Push-to-talk (hold & release) |
| Option+V | Cycle verbosity level |
| Escape | Cancel current action |

### Hotkey Presets

You can choose from 4 push-to-talk hotkey presets during onboarding or in Settings:

| Preset | Keys | Notes |
|--------|------|-------|
| **Control+Space** *(recommended)* | `^Space` | Doesn't conflict with Spotlight or IME |
| Option+Space | `⌥Space` | Classic, but may type special characters |
| Command+Shift+V | `⌘⇧V` | Safe, unlikely to conflict |
| Fn+Space | `FnSpace` | Minimal, uses the Globe key |

## Voice Commands

### Voice Prefixes (Target Routing)

| Prefix | Target | Example |
|--------|--------|---------|
| *(none)* | Terminal.app | "git status" |
| "terminal ..." | Terminal.app | "terminal list all docker containers" |
| "claude ..." | Claude Code CLI | "claude explain this function" |
| "code ..." | VS Code / Cursor | "code open the readme file" |

### Natural Language Mappings

| Say | Executes |
|-----|----------|
| "list files" / "show files" | `ls -la` |
| "where am I" / "show directory" | `pwd` |
| "go to Documents" | `cd Documents` |
| "create folder my-project" | `mkdir -p my-project` |
| "git status" | `git status` |
| "npm run build" | `npm run build` |
| Any shell command | Executed as-is |

### Destructive Command Safety

VOX detects potentially dangerous commands and requires confirmation:

- `rm -rf`, `rm -r` — recursive deletion
- `sudo` — elevated privileges
- `DROP TABLE`, `TRUNCATE` — database destruction
- `git push --force` / `git reset --hard` — git history rewriting
- `docker rm` — container removal
- `shutdown`, `reboot` — system commands
- `chmod 777` — insecure permissions

When detected, VOX shows a floating confirmation panel and says *"Destructive command detected. Say confirm or cancel."*

## Verbosity Levels

Cycle through levels with **Option+V** or configure per-app in Settings:

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
│   ├── TargetApp.swift         — Terminal, Claude Code, VS Code, etc.
│   ├── VoxCommand.swift        — Command history model with Codable
│   ├── VoxSettings.swift       — @AppStorage settings + hotkey presets
│   └── VOXVersion.swift        — Centralized version constant
├── Services/
│   ├── HexBridge.swift         — Clipboard-based Hex STT integration
│   ├── TerminalExecutor.swift  — Shell execution via Process API
│   ├── ResponseProcessor.swift — Verbosity-aware output summarization
│   ├── TTSEngine.swift         — Text-to-speech via NSSpeechSynthesizer
│   ├── HotkeyManager.swift     — CGEventTap global hotkey interception
│   ├── CommandRouter.swift     — NLP prefix routing + natural language
│   ├── CommandHistory.swift    — Persistent command log (JSON)
│   └── SafetyChecker.swift     — Destructive command & secret detection
├── Views/
│   ├── MenuBarView.swift       — Menu bar dropdown with status + actions
│   ├── PushToTalkOverlay.swift — Floating HUD during listening
│   ├── SettingsView.swift      — 5-tab settings window
│   ├── HistoryView.swift       — Searchable command history
│   ├── OnboardingView.swift    — 6-step first-run wizard
│   └── DestructiveConfirmView.swift — Floating safety confirmation
├── AppState.swift              — Central coordinator + panel management
└── VOXApp.swift                — @main entry point with MenuBarExtra
```

### Key Design Decisions

- **Menu bar-only app** — Uses `NSApp.setActivationPolicy(.accessory)` to live in the menu bar without a dock icon
- **CGEventTap over NSEvent monitors** — CGEventTap can consume (suppress) key events at the OS level, preventing hotkey characters from leaking into foreground apps. Falls back to NSEvent monitors if Accessibility isn't granted.
- **Floating NSPanel overlays** — Push-to-talk HUD and destructive command confirmation use `NSPanel` with `.nonactivatingPanel` + `.hudWindow` styles, so they appear on top without stealing focus
- **Hex clipboard bridge** — Hex transcribes speech and places text on the clipboard. VOX monitors `NSPasteboard` for changes. This requires no changes to Hex itself.
- **Reactive state with Combine** — `AppState` uses `@Published` properties and `$appMode.sink` for reactive panel management

## Hex Integration

VOX uses [Hex](https://hex.kitlangton.com/) for on-device speech-to-text:

1. **Install Hex** from [hex.kitlangton.com](https://hex.kitlangton.com/)
2. **Start Hex** — it runs in your menu bar alongside VOX
3. **Speak** — Hex transcribes your voice using WhisperKit (Core ML) on your Mac
4. **VOX receives** the transcription via clipboard monitoring

No audio data ever leaves your Mac. Hex supports multiple Whisper model sizes (tiny through large-v3) with different accuracy/speed tradeoffs.

## Settings

VOX offers a comprehensive 5-tab settings window:

- **General** — Launch at login, theme (dark/light/system), language preferences
- **Voice Input** — STT engine selection, activation mode, Whisper model size
- **TTS Output** — Engine selection, speed, volume, interrupt behavior
- **Apps** — Per-app verbosity, target detection, command prefixes
- **Advanced** — Summarization method, Ollama integration, command timeout, safety patterns

## Roadmap

| Version | Milestone | Status |
|---------|-----------|--------|
| v0.1 | Terminal + Claude Code CLI + macOS Say TTS + 90 tests | Done |
| v0.2 | Floating panels + destructive confirm + menu bar improvements | Done |
| v0.3 | App icon + .app bundle + onboarding + CGEventTap hotkeys | **Current** |
| v0.4 | Kokoro/Piper/ElevenLabs TTS + VS Code/Cursor/Windsurf | Planned |
| v0.5 | Plugin system + Git/Docker voice commands | Planned |
| v1.0 | Production ready + Homebrew install | Planned |

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 6 / SwiftUI |
| STT | [Hex](https://hex.kitlangton.com/) (WhisperKit/Parakeet, on-device) |
| TTS | macOS NSSpeechSynthesizer (MVP); Kokoro, Piper, ElevenLabs (planned) |
| Hotkeys | CGEventTap (consumes events) with NSEvent fallback |
| Platform | macOS 14+ (Apple Silicon optimized) |
| Testing | XCTest — 90 unit + integration tests |
| Build | Swift Package Manager |

## Privacy & Security

- **No cloud required** — All STT and TTS processing happens on your Mac
- **No telemetry** — Zero analytics, zero tracking, zero data collection
- **No audio storage** — Voice audio is never saved; only transcriptions are logged (optionally)
- **Secret masking** — Commands containing passwords, API keys, or tokens are masked in history
- **Open source** — Full source code is public and auditable

## Contributing

Contributions are welcome! Please open an issue or pull request.

### Development Setup

```bash
git clone https://github.com/RichardTheuws/VOX-app.git
cd VOX-app
swift build
swift test  # 90 tests should pass
```

## License

MIT License — see [LICENSE](LICENSE)

## Brand

Part of the [tools.theuws.com](https://tools.theuws.com) ecosystem.

---
Version 0.3.1
