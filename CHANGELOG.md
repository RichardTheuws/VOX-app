# Changelog

All notable changes to VOX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.6.2] - 2026-02-11

### Changed
- **PRD rewritten to v2.0.0**: Complete rewrite of `docs/PRD.md` from voice-operated assistant (v0.1.0, 936 lines) to Hex companion architecture (v2.0.0, 773 lines). Now accurately documents the current passive monitoring architecture, Hex Bridge file monitoring, terminal output stabilization, heuristic summarization engine, and updated roadmap (v0.7–v1.0).

## [0.6.1] - 2026-02-11

### Fixed
- **Onboarding Step 3 auto-starts monitoring**: Voice test now automatically starts listening for Hex transcriptions when Step 3 appears, removing the need to click a separate "Start Test" button.
- **Monitoring stops on navigation**: Going back to Step 2 properly stops HexBridge monitoring.
- **Hex launch auto-retry**: Clicking "Launch Hex" now automatically starts monitoring after Hex launches.

## [0.6.0] - 2026-02-11

### Changed
- **VOX is now a pure Hex companion**: Stripped all push-to-talk, command execution, and accessibility code. VOX only monitors terminal output and reads it back via TTS.
- **Onboarding simplified from 6 → 3 steps**: (1) Hex install, (2) TTS engine, (3) Voice test. Removed Accessibility, Microphone, and Hotkey Selection steps.
- **Menu bar icon**: Changed from microphone to ear — VOX is a listener, not a speaker.
- **Settings simplified**: Removed Voice tab (STT engine picker, activation mode), Keyboard Shortcuts section, Routing section, and Safety section. Renamed "Command timeout" to "Monitor timeout".

### Removed
- **HotkeyManager** (214 lines): CGEventTap push-to-talk system — Hex handles all voice input.
- **CommandRouter** (130 lines): Command routing/interpretation — VOX no longer executes commands.
- **TerminalExecutor** (114 lines): Shell command execution via Process API — VOX only reads terminal output.
- **SafetyChecker** (107 lines): Destructive command detection — nothing to check when not executing.
- **PushToTalkOverlay** (80 lines): Floating listening HUD — no more push-to-talk.
- **DestructiveConfirmView** (113 lines): Destructive command confirm dialog — no more safety checks.
- **AppMode cases**: `.listening`, `.processing`, `.confirmingDestructive` — simplified to `.idle` and `.monitoring`.
- **Settings**: `pushToTalkHotkey`, `sttEngine`, `activationMode`, `whisperModel`, `confirmDestructive` properties and related enums (`PushToTalkHotkey`, `STTEngine`, `ActivationMode`, `WhisperModel`).
- **58 tests** removed with deleted services: CommandRouterTests (12), TerminalExecutorTests (12), SafetyCheckerTests (25), IntegrationTests (9).

### Technical
- `ExecutionResult` struct moved from deleted `TerminalExecutor.swift` to `ResponseProcessor.swift`
- AppState stripped from ~600 to ~290 lines — removed 5 services, 3 window managers, 10+ methods
- Net code reduction: ~1,500+ lines removed across 16 files

## [0.5.0] - 2026-02-11

### Added
- **Monitor mode**: VOX now monitors Terminal.app/iTerm2 output when Hex dictation is sent to those apps. Instead of executing the transcription as a command (which Hex already pasted), VOX reads the app's response and speaks it via TTS. This is the core "talk to your terminal, hear what matters" experience.
- **TerminalReader service**: New service that reads Terminal.app and iTerm2 content via AppleScript (`osascript`). Supports snapshot-and-diff to extract only new output, with configurable stabilization delay and timeout.
- **AppMode.monitoring**: New app state for when VOX is waiting for terminal output to stabilize. Shows eye icon in menu bar and "Monitoring..." status.

### Changed
- **HexBridge callback now passes full `HexHistoryEntry`** instead of just the text string. This gives AppState access to `sourceAppBundleID` and `sourceAppName` to determine routing.
- **Smart routing based on source app**: When Hex dictates into Terminal/iTerm2, VOX enters monitor mode. Dictation into other apps (WhatsApp, Notes, etc.) is ignored — VOX only activates for developer tools.
- **Menu bar text updated**: "Monitoring Hex — dictate in Terminal" (was "dictate to execute").

### Technical
- `HexBridge.onTranscription` type changed from `((String) -> Void)` to `((HexHistoryEntry) -> Void)`
- `TerminalReader.waitForNewOutput()` uses snapshot-diff with 1.5s stabilization delay and configurable timeout
- `AppState.monitorTerminalResponse()` takes terminal snapshot, waits for output, processes through ResponseProcessor, speaks via TTS
- Bundle IDs for monitorable apps: `com.apple.Terminal`, `com.googlecode.iterm2`

## [0.4.1] - 2026-02-11

### Fixed
- **HexBridge: clipboard monitoring replaced with file monitoring**: Hex's default mode copies text to clipboard, simulates Cmd+V, then **restores the original clipboard** within milliseconds. VOX's 0.15s clipboard polling could never catch this. Now monitors Hex's `transcription_history.json` file instead — reliable, no timing issues, includes source app metadata.
- **Root cause identified**: Hex setting `copyToClipboard: false` + `useClipboardPaste: true` means clipboard content is transient. The transcription_history.json file persists every dictation with timestamp, text, source app, and duration.

### Changed
- HexBridge now uses `FileManager` to poll Hex's history file (0.3s interval) instead of `NSPasteboard` clipboard monitoring.
- Removed all clipboard-related heuristics (`isLikelyTranscription`, `lastClipboardChangeCount`, etc.) — no longer needed.
- Added `HexHistoryEntry` model to decode Hex's JSON history format.
- `seedLastTimestamp()` on init prevents re-processing old transcriptions on app launch.

## [0.4.0] - 2026-02-10

### Changed
- **Architecture: auto-process mode**: VOX now automatically processes any Hex transcription when idle — no push-to-talk hotkey required. Dictate with Hex's own hotkey, VOX detects the transcription and executes the command immediately.
- **Push-to-talk is now optional**: The hotkey (Control+Space etc.) still works if Accessibility is granted, but VOX is fully functional without it. This eliminates the "accessibility not detected after rebuild" friction.
- **Menu bar shows Hex monitoring status**: Green dot + "Monitoring Hex — dictate to execute" when Hex is running. Orange warning when push-to-talk hotkey needs Accessibility.
- **Onboarding voice test simplified**: Replaced hold-to-talk button with simple "Start Test" that monitors for Hex transcription. Added 3-step "How VOX works" explanation. Push-to-talk shown as optional.
- **HotkeyManager graceful degradation**: `isHotkeyActive` published property tracks whether CGEventTap succeeded. No more NSEvent fallback that didn't work anyway.

### Removed
- NSEvent global/local monitor fallback in HotkeyManager (was ineffective without Accessibility)
- Hold-to-talk test button in onboarding (replaced with Hex monitoring test)

## [0.3.2] - 2026-02-10

### Fixed
- **Accessibility detection polling**: Onboarding now polls `AXIsProcessTrusted()` every 2 seconds on the accessibility step, auto-detecting when the user grants access in System Settings (no more manual "Check Again" needed).
- **"Open System Settings" button**: Direct link to Privacy & Security → Accessibility, with note about re-granting after rebuilds.
- **Voice test clarity**: Test step now shows Hex running status, auto-launches Hex if not running, and clearly explains the user must dictate with Hex's own hotkey. Changed icon from mic to ear ("Waiting for Hex...") to set correct expectations.
- **Voice test error messages**: More helpful guidance when no transcription is received (distinguishes Hex not running vs. no dictation detected).
- **Settings hotkey display**: Replaced hardcoded "⌥Space" with a Picker showing all 4 hotkey presets (Control+Space, Option+Space, ⌘⇧V, Fn+Space). Users can now change their push-to-talk hotkey from Settings.
- **Live hotkey updates**: Changing the push-to-talk hotkey in Settings now applies immediately via `UserDefaults.didChangeNotification` observer — no restart required.

## [0.3.1] - 2026-02-10

### Added
- **CGEventTap hotkey interception**: Completely rewrote HotkeyManager to use CGEventTap instead of NSEvent monitors. Key events are now consumed (suppressed) at the OS level, preventing characters from leaking into foreground apps (fixes Option+Space typing spaces).
- **Configurable hotkey presets**: 4 push-to-talk hotkey options — Control+Space (default), Option+Space, Command+Shift+V, Fn+Space. Configurable in onboarding and Settings.
- **PushToTalkHotkey enum**: New model with CGEventFlags, key codes, display names, and short labels for each preset.
- **Interactive voice test**: Step 6 of onboarding now includes a real hold-to-talk button that records via Hex, shows transcription, and speaks it back via TTS.
- **Hotkey selection step**: Step 4 of onboarding lets users choose their preferred push-to-talk hotkey.
- **NSEvent fallback**: If CGEventTap fails (no Accessibility permission), gracefully falls back to NSEvent global/local monitors.
- **Comprehensive README**: Extensive documentation with architecture details, design decisions, hotkey presets, privacy section, and development setup.

### Changed
- Default push-to-talk hotkey changed from Option+Space to **Control+Space** (less likely to conflict with system shortcuts or IME)
- Onboarding expanded from 5 to **6 steps** (added Hotkey Selection and Voice Test)
- Accessibility detection now uses `AXIsProcessTrustedWithOptions` with prompt trigger (properly shows macOS permission dialog)
- `MainActor.assumeIsolated` used in CGEventTap C callback for Swift 6 strict concurrency compliance

### Fixed
- **Option+Space typing spaces**: NSEvent monitors are read-only and can't suppress events. CGEventTap returns nil to fully consume matched hotkey events.
- **Accessibility not detected after granting**: Now uses `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt` to trigger the system dialog and properly re-checks after a delay.

## [0.3.0] - 2026-02-10

### Added
- **Onboarding wizard**: 5-step setup wizard with Accessibility, Microphone, Hex, TTS, and Test steps
- **Accessibility permissions check**: Step 1 of onboarding verifies and guides Accessibility access for global hotkeys
- **Hex status indicator**: Menu bar dropdown now shows if Hex is running (green) or not (orange)
- **"Setup Wizard..." menu item**: Re-run onboarding from the menu bar at any time
- App icon — custom VOX icon with microphone + waveform design in brand colors
- Build script (`scripts/build-app.sh`) to create proper macOS .app bundle
- Info.plist with bundle ID `com.theuws.vox`, microphone usage description, LSUIElement
- App can now be launched from Finder, Spotlight, or /Applications

### Changed
- Onboarding window now temporarily switches to regular activation policy for visibility
- Onboarding expanded from 4 to 5 steps (added Accessibility check as step 1)
- `showOnboarding()` is now public for menu bar access

## [0.2.0] - 2026-02-10

### Changed
- Onboarding now shows as standalone window on first launch (PRD compliance)
- Push-to-talk overlay is now a floating HUD panel centered on screen (PRD compliance)
- Destructive command confirm is now a floating panel centered on screen (PRD compliance)
- MenuBarExtra always shows the dropdown menu (no more conditional view swapping)
- Version number is now dynamic via VOXVersion constant

### Added
- Escape key handler to cancel current action (listening, destructive confirm, TTS)
- cancelCurrentAction() method on AppState for Escape key
- NSPanel-based floating windows for push-to-talk and destructive confirm
- VOXVersion model for centralized version management
- AppState mode observer for automatic panel show/hide

## [0.1.1] - 2026-02-10

### Fixed
- App now auto-starts services when onboarding already completed
- Destructive command confirm/cancel buttons now work correctly
- App runs as menu bar-only (no Dock icon) via NSApp.setActivationPolicy(.accessory)

### Added
- 90 unit + integration tests covering all core services
- Test target in Package.swift
- CommandRouterTests (12 tests)
- ResponseProcessorTests (15 tests)
- SafetyCheckerTests (25 tests)
- TerminalExecutorTests (12 tests)
- ModelTests (17 tests for VerbosityLevel, TargetApp, VoxCommand)
- IntegrationTests (9 full-pipeline tests)

## [0.1.0] - 2026-02-10

### Added
- Initial project structure and PRD
- macOS menu bar app skeleton with SwiftUI
- Push-to-talk overlay with waveform visualization
- Hex clipboard bridge for speech-to-text input
- Terminal command execution via Process API
- Response processor with 4 verbosity levels (Silent, Ping, Summary, Full)
- Heuristic summarization engine for command output
- macOS native TTS (say) integration
- Command history with persistence
- Destructive command safety checker
- Settings UI with 5 tabs (General, Voice, Apps, TTS, Advanced)
- Onboarding flow for first-run setup
- Global hotkey support (Option+Space for push-to-talk)
- Brand styling aligned with tools.theuws.com design system
