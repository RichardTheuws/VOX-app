# Changelog

All notable changes to VOX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
