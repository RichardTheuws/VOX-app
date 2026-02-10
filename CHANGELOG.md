# Changelog

All notable changes to VOX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
