# Changelog

All notable changes to VOX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
