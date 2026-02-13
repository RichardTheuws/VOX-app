# Changelog

All notable changes to VOX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-02-13

### Added
- **Claude Desktop support**: VOX now monitors Claude Desktop (`Claude.app`) — both Chat and Code modes. Claude Desktop is Electron-based (like Cursor/VS Code/Windsurf), so it uses the same Accessibility API with chat fragment assembly. Bundle ID: `com.anthropic.claudefordesktop`.
- **Per-app sound pack selection**: When an app's verbosity is set to "Notice", an additional sound pack picker appears below the app row in Settings → Apps. Each app can now have its own sound pack (WarCraft, Mario, Zelda, C&C, System Sounds, TTS, or Custom) — no more one-size-fits-all. Falls back to the global sound pack when no per-app setting is configured.
- **10 new tests**: Claude Desktop model tests (4 — bundle ID, isTerminalBased, voicePrefixes, unique bundle IDs), per-app sound pack tests (6 — default fallback, per-app set/get, custom pack fallback/set, notice mode routing, Claude Desktop with Zelda pack). Total: 128 tests (was 118).

### Changed
- **ResponseProcessor.process() now accepts `target` parameter**: Per-app sound pack routing requires knowing which app triggered the notice. The `target: TargetApp` parameter is passed from AppState's monitoring flow.
- **TargetApp enum expanded to 7 cases**: Added `.claudeDesktop` alongside terminal, iterm2, claudeCode, vsCode, cursor, windsurf.
- **Accessibility permission hint updated**: Settings → Apps now mentions Claude Desktop alongside Cursor, VS Code, and Windsurf in the AX permission requirement text.

### Technical
- `TargetApp.swift` — Added `.claudeDesktop` case with bundleIdentifier `"com.anthropic.claudefordesktop"`, voicePrefixes `["claude desktop", "desktop"]`, `isTerminalBased: false`, tier `.must`
- `AppState.swift` — Added `"com.anthropic.claudefordesktop"` to `monitorableBundleIDs`, passes `target` to `responseProcessor.process()`
- `VoxSettings.swift` — Added `soundPack(for:)`, `setSoundPack(_:for:)`, `customSoundPackName(for:)`, `setCustomSoundPackName(_:for:)` with UserDefaults keys `soundPack_<app>` and `customSoundPack_<app>`, falling back to global settings
- `ResponseProcessor.swift` — `process()` signature gains `target: TargetApp`, notice mode uses `settings.soundPack(for: target)` and `settings.customSoundPackName(for: target)`
- `SettingsView.swift` — Conditional `NoticeSoundPack` Picker in Apps tab (visible when app verbosity == `.notice`), `soundPackBinding(for:)` helper, updated AX hint text
- `ModelTests.swift` — 4 new Claude Desktop tests + updated `testAllCases` count to 7
- `ResponseProcessorTests.swift` — All 27 existing `process()` calls updated with `target: .terminal`, 6 new per-app sound pack tests

## [1.1.0] - 2026-02-13

### Added
- **Adaptive two-phase stabilization**: Long-running commands (Claude Code sessions of 30-40+ minutes) are now properly monitored until completion. VOX no longer prematurely summarizes output when the AI pauses to think or execute tools.
  - **Phase 1 (Active)**: Fast polling at 0.5s interval. After 3 seconds of no changes, moves to Phase 2.
  - **Phase 2 (Verifying)**: Exponential backoff polling (2s → 5s → 10s). After 15 more seconds of stability, confirms the command is truly done. If content changes, resets to Phase 1.
- **Terminal prompt detection**: Shell prompt patterns (bash `$`, zsh `%`, starship `❯`, root `#`) are detected for instant completion — no 15-second wait needed for short commands.
- **Exponential backoff polling**: CPU usage reduced from ~8,000 polls to ~500 polls over a 40-minute session. Poll interval adapts: 0.5s (active) → 2s → 5s → 10s (waiting).
- **12 new tests**: Adaptive poll interval tests (4), shell prompt detection tests (8 — bash, zsh, starship, root, negative cases, multiline, trailing empty lines, long lines). Total: 118 tests (was 106).

### Changed
- **Command timeout default**: Increased from 30 seconds to 3,600 seconds (1 hour). Long Claude Code sessions now complete naturally instead of timing out.
- **Stabilization delay**: Increased from 1.5s to 3s initial stabilization + 15s confirmation. Prevents premature "done" detection when AI pauses briefly.

### Technical
- `TerminalReader.swift` — New `MonitorPhase` enum (`.active`, `.verifying`), `adaptivePollInterval()` static method with 4-tier backoff, `endsWithShellPrompt()` regex-based prompt detection, complete refactor of `waitForNewOutput()` with two-phase algorithm
- `VoxSettings.swift` — `commandTimeout` default changed from 30 to 3600
- `AppState.swift` — Updated `monitorTerminalResponse()` call with new parameters: `initialStabilizeDelay: 3.0`, `confirmationDelay: 15.0`, `usePromptDetection: true`
- `TerminalReaderDiffTests.swift` — 12 new tests for adaptive polling and prompt detection

## [1.0.2] - 2026-02-13

### Fixed
- **Accessibility permission no longer prompts on every launch**: The AX permission prompt was shown on every app start because the "already prompted" flag was an in-memory instance property that reset on launch. Now persisted via `UserDefaults` — VOX prompts once on first launch, then relies on the Settings UI for subsequent permission grants.

## [1.0.1] - 2026-02-13

### Fixed
- **Ollama summaries now work at runtime**: The `isServerRunning` check in ResponseProcessor used a cached `@Published` property that was never updated during the normal monitoring flow, causing Ollama summarization to be silently skipped. Replaced with a live `checkServer()` call that performs an actual HTTP health check before each summarization attempt.

## [1.0.0] - 2026-02-12

### Added
- **Adaptive voice selection**: VOX now auto-detects the language of text being spoken (Dutch, English, German) using Apple's NLLanguageRecognizer and selects a matching voice. Users only need to set a gender preference (male/female) — no more manual voice picker.
- **VoiceGender enum**: New setting with `.female` (default) and `.male` options. Replaces the per-voice Edge TTS picker.
- **LanguageDetector service**: New utility wrapping `NLLanguageRecognizer` constrained to NL/EN/DE. Requires minimum 10 chars for reliable detection, falls back to English.
- **German language support**: `ResponseLanguage` enum now includes `.german` ("Deutsch") alongside Dutch and English.
- **Localized heuristic summaries**: ALL summary strings in ResponseProcessor are now localized for NL/EN/DE — timeout messages, success/error summaries, git status, build output, Claude output, and generic summaries.
- **`localized(en:nl:de:)` helper**: New method on ResponseProcessor for tri-lingual string selection based on `effectiveLanguageCode()`.
- **Edge TTS adaptive voice mapping**: `adaptiveEdgeTTSVoice(for:)` maps (language × gender) to Microsoft Neural voices — NL: Colette/Maarten, EN: Jenny/Guy, DE: Amala/Conrad.
- **macOS native adaptive voices**: `preferredVoice(for:)` now filters system voices by detected language locale + gender preference, with multi-level fallbacks (lang+gender+premium → lang+gender → lang+premium → lang-only).
- **17 new tests**: LanguageDetectorTests (4), AdaptiveEdgeTTSVoiceTests (4), LocalizedSummaryTests (5), VoiceGenderTests (4). Total: 106 tests (was 89).

### Changed
- **Settings UI simplified**: Replaced 6-option Edge TTS voice Picker with a simple male/female gender Picker that works across all TTS engines. Added explainer text: "VOX detects the language automatically and picks a matching voice."
- **README completely rewritten**: New sections for Supported Apps table, TTS Engines comparison, Adaptive Voice Selection, dual reading paths (AppleScript + Accessibility API), Notice Mode options, code signing setup. Updated architecture tree, roadmap (all versions through v1.0), tech stack, and test count (106).

### Technical
- `LanguageDetector.swift` — New file: NLLanguageRecognizer wrapper with 10-char minimum threshold
- `TTSEngine.swift` — `adaptiveEdgeTTSVoice(for:)`, rewritten `preferredVoice(for:)` with language+gender filtering, fully qualified `NSSpeechSynthesizer.VoiceAttributeKey` keys to avoid enum name collision with `VoiceGender`
- `ResponseProcessor.swift` — `localized(en:nl:de:)` helper, all summary methods localized, `effectiveLanguageCode()` handles German
- `VoxSettings.swift` — `VoiceGender` enum, `voiceGender` property, `.german` case in `ResponseLanguage`
- `SettingsView.swift` — Gender picker replaces voice picker, Edge TTS section simplified
- `AdaptiveVoiceTests.swift` — 17 new tests with proper `@AppStorage` isolation (setUp/tearDown resets)

## [0.10.5] - 2026-02-12

### Fixed
- **Critical: VOX now reads AI response instead of user prompt**. The v0.10.4 chatAssembly algorithm returned `substantialGroups.last` — the last large text block in tree order. In Cursor's AX tree, the user's latest prompt (depth=34, ~105 chars) appears AFTER the AI response (depth=33, ~428 chars), so VOX was reading back the user's own prompt. Fixed by identifying the "AI response depth" (the depth with the largest single group — AI responses are 400-1000+ chars, user prompts are 75-120 chars) and returning the last group at that depth.

### Added
- **Self-signed code signing for persistent AX permissions**: New `scripts/create-signing-cert.sh` creates a "VOX Developer" self-signed certificate for code signing. `scripts/build-app.sh` now automatically signs the binary with this certificate. This makes macOS TCC recognize VOX across rebuilds (same code signing identity = same CDHash behavior), so Accessibility permission is granted once and persists.
- **`--identifier com.vox.app`** in codesign for stable bundle identification.

### Technical
- `AccessibilityReader.swift` — Phase 4 now finds AI response depth via `max(by:)` on group size, then filters to that depth instead of blindly taking `substantialGroups.last`
- `scripts/build-app.sh` — Added Step 8: code signing with "VOX Developer" certificate, with graceful fallback if certificate not found
- `scripts/create-signing-cert.sh` — New script: generates self-signed RSA 2048-bit code signing certificate, imports into login keychain, sets key partition list for codesign access

## [0.10.4] - 2026-02-12

### Fixed
- **AI chat response reading finally works**: VOX now correctly reads Cursor's AI chat panel responses. The root cause: Chromium renders chat text as hundreds of tiny `AXStaticText` fragments (~12-18 chars each) at consistent AX tree depths. The previous harvest strategy filtered these out (each fragment was below the 80-char minimum). New **Chat Fragment Assembly** strategy collects ALL `AXStaticText` elements, groups consecutive same-depth fragments, concatenates them, and returns the last substantial block (= latest AI response).

### Added
- **`assembleChatFragments()` method**: New Strategy 0 (highest priority) in AccessibilityReader. Collects all AXStaticText fragments from the window tree with their depths, filters to chat depth (>= 30), groups consecutive same-depth fragments into message blocks, returns the last block with > 100 chars concatenated.
- **`collectStaticTextFragments()` helper**: Tree traversal that collects only AXStaticText element values with their tree depths. No minimum character filter — needed to capture all 12-18 char fragments for reassembly.
- **Chat depth constants**: `chatMinDepth` (30) excludes UI chrome; `chatMinGroupChars` (100) filters out meta-labels like "Thought", "Agent".

### Technical
- `AccessibilityReader.swift` — New `assembleChatFragments()` as Strategy 0 before harvest, `collectStaticTextFragments()` helper, `chatMinDepth`/`chatMinGroupChars` constants. Strategy order: 0 (chatAssembly) → 1 (harvest) → 2 (system) → 3 (focused)

## [0.10.3] - 2026-02-12

### Added
- **Comprehensive AX tree diagnostic**: One-time deep diagnostic dump on first read that scans the FULL window AX tree (maxDepth=60, up to 5000 elements). Writes detailed analysis to `~/Library/Logs/VOX-ax-diagnostic.log`.
- **AXWebArea detection**: Diagnostic identifies ALL webview elements (AXWebArea) in the window — critical for finding Cursor's chat panel vs editor panel.
- **Chromium DOM attributes**: Diagnostic checks `AXDOMIdentifier`, `AXDOMClassList`, and `AXARIALive` attributes that Chromium may expose for web elements.
- **StringForRange text extraction**: Diagnostic reads text from elements that expose `kAXNumberOfCharactersAttribute` + `kAXStringForRangeParameterizedAttribute` — catches text hidden from standard value/description/title attributes.
- **AXStaticText inventory**: Diagnostic specifically logs all `AXStaticText` elements (Chromium's text nodes) to reveal whether chat content exists as fragmented text.
- **Role distribution**: Full count of every AX role type in the tree for structural analysis.
- **Text fragment analysis**: All text fragments (no minimum) with size distribution (<10, 10-50, 50-80, 80+ chars) and detailed dump of fragments >30 chars.

### Technical
- `AccessibilityReader.swift` — Added `hasDumpedDiagnostic` flag, `dumpFullDiagnostic()` method with nested `scanTree()` and `countTextInSubtree()`, checks AXDOMIdentifier/AXDOMClassList/AXARIALive/kAXNumberOfCharactersAttribute/kAXStringForRangeParameterizedAttribute

## [0.10.2] - 2026-02-12

### Fixed
- **AI chat response reading**: VOX now finds Cursor's AI response text regardless of where the cursor is focused. Previously, VOX followed the focused input field and only found UI strings like "Add a follow-up" instead of the actual AI response.
- **Deep content harvest strategy**: New primary reading strategy scans the entire focused window AX tree (maxDepth=50) for substantial text blocks (> 80 chars). Reads kAXValue, kAXDescription, AND kAXTitle from every element — not just specific roles. This finds AI chat content that lives in a sibling subtree of the input field.
- **Content threshold filtering**: All strategies now require > 80 chars minimum to accept text as valid content. Prevents UI labels ("Add a follow-up", "Review", "53 Files") from being mistaken for real content.

### Technical
- `AccessibilityReader.swift` — Complete rewrite: new `harvestWindowContent()` as primary strategy, `collectAllText()` reads all attributes from all elements, `HarvestedText` struct with role/attribute/depth metadata, `titleValue()` helper, `minimumContentLength` constant (80), removed role-specific `collectTextValues()` and `textRoles`

## [0.10.1] - 2026-02-12

### Fixed
- **Accessibility permission auto-request**: VOX now detects when AX permission is missing and shows the System Settings prompt automatically (once per session). Previously, rebuilds silently invalidated the permission without user feedback.
- **AXManualAccessibility for Electron apps**: VOX now explicitly enables Chromium's accessibility tree via `AXManualAccessibility` attribute before reading content. Electron (Cursor, VS Code, Windsurf) disables its AX tree by default for performance.
- **System-wide focused element (Strategy 0)**: New reading strategy uses `AXUIElementCreateSystemWide()` to bypass app-level AX tree issues. Verifies PID ownership, reads value/description, and traverses parent chain for content containers. This is now the first strategy attempted before app-level approaches.
- **Extended AX element support**: `collectTextValues()` now reads `AXGroup` elements (via `kAXDescriptionAttribute`) and `AXWebArea` elements (via `kAXValueAttribute`), covering more of Chromium's AX tree structure.
- **Enhanced AX diagnostics**: Debug logging now includes `AXManualAccessibility` return status, system-wide focused element details (role, PID, value/description sizes), window identity (role, title), and direct children structure (roles, descriptions, child counts). Logs to `~/Library/Logs/VOX-ax-debug.log`.

### Technical
- `AccessibilityReader.swift` — Added `hasRequestedPermission` flag, `enableAccessibilityTree(for:)` with `AXManualAccessibility`, `readSystemFocusedText(expectedPID:)` Strategy 0, `descriptionValue(of:)` helper, extended `collectTextValues()` for AXGroup + AXWebArea, enhanced window diagnostics
- `TerminalReader.swift` — Added debug logging to `waitForNewOutput()` (poll count, change count, nil count, content sizes)

## [0.10.0] - 2026-02-12

### Added
- **ElevenLabs TTS**: Premium multilingual TTS via ElevenLabs REST API (`eleven_multilingual_v2` model). Excellent Dutch, English, and German voice quality. Configurable API key and voice ID in Settings. Falls back to native macOS TTS on error.
- **Edge TTS**: Free Microsoft Neural TTS voices via `edge-tts` CLI. Includes 6 voice presets: Dutch (Colette, Maarten), English (Jenny, Guy), German (Amala, Conrad). Installation status shown in Settings with guidance.
- **Audio playback engine**: New `AVAudioPlayer`-based playback for ElevenLabs and edge-tts MP3 output, with volume and speed control. Replaces direct `NSSpeechSynthesizer` for external TTS engines.
- **Smart summarization bypass**: Short responses (≤2 meaningful lines, ≤2 sentences, ≤200 chars) are now read directly via TTS without Ollama overhead. Enables instant conversational feedback for quick terminal responses.
- **AX content diff (set-based)**: New `extractAXNewContent()` method in TerminalReader uses set-based line comparison for Electron apps (Cursor, VS Code, Windsurf) where content changes in-place rather than appending. Fixes "No new output detected" issue.
- **TTS engine configuration UI**: Settings → TTS now shows engine-specific configuration: ElevenLabs API key + voice ID fields, Edge TTS voice picker with 6 presets, installation status indicator.
- **16 new tests**: 9 TerminalReaderDiffTests (AX set-based diff, terminal line-append diff, edge cases), 7 ResponseProcessorTests (smart summarization bypass, TTSEngineType, edge-tts). Total: 89 tests (was 73).

### Changed
- **TerminalReader diff strategy**: `extractNewContent()` now accepts `isTerminalBased` parameter. Terminal apps (Terminal.app, iTerm2) use existing line-append diff; AX apps (Cursor, VS Code, Windsurf) use new set-based diff that detects in-place content changes.
- **TTSEngine multi-backend**: `speak()` now routes to native macOS, ElevenLabs, or edge-tts based on configured engine. Each external engine falls back to native on failure.
- **TTSEngineType enum expanded**: Added `.edgeTTS` and `.elevenLabs` cases alongside existing `.macosSay`, `.kokoro`, `.piper`, `.disabled`.
- **ResponseProcessor summary mode**: Added early-exit path for short output before Ollama/heuristic routing, improving response latency for conversational development flow.

### Technical
- `TerminalReader.swift` — `extractAXNewContent()` with `Set<String>` comparison, `isTerminalBased` flag in `waitForNewOutput()`
- `TTSEngine.swift` — `speakWithElevenLabs()` async REST client, `speakWithEdgeTTS()` Process-based CLI wrapper, `playAudioFile()` AVAudioPlayer helper, `findEdgeTTSBinary()` multi-path search, `AudioDelegate` for playback completion
- `VoxSettings.swift` — `elevenLabsAPIKey`, `elevenLabsVoiceID`, `edgeTTSVoice` @AppStorage properties
- `ResponseProcessor.swift` — Smart summarization bypass with 3-condition AND logic (lines ≤ 2, sentences ≤ 2, chars ≤ 200)
- `SettingsView.swift` — Engine-specific configuration sections, `edgeTTSInstalled` state check

## [0.9.0] - 2026-02-11

### Added
- **Accessibility API support**: VOX can now monitor and read back responses from **Cursor**, **VS Code**, and **Windsurf**. Previously only Terminal.app and iTerm2 were supported (via AppleScript). Electron-based editors use the macOS Accessibility API (`AXUIElement`) to read the focused text element.
- **AccessibilityReader service**: New service that reads application content via `AXUIElementCopyAttributeValue`. Uses a two-strategy approach: (1) read the focused element's text value directly, (2) fallback to traversing the focused window's AX tree for text-bearing elements (`AXTextArea`, `AXStaticText`, `AXTextField`).
- **Accessibility permission UI**: Settings → Apps tab now shows Accessibility permission status with a green/orange indicator. "Grant Permission" button opens System Settings when not yet granted. Per-app warnings shown for Cursor/VS Code/Windsurf when permission is missing.
- **15 new tests**: AccessibilityReader permission check, nil-safety for unknown/empty bundle IDs, TerminalReader AX delegation for Cursor/VS Code/Windsurf, no-regression for Terminal/iTerm2, TargetApp bundle ID lookups, terminal-based vs AX-based app classification. Total: 73 tests (was 58).

### Changed
- **TerminalReader delegates to AccessibilityReader**: `readContent(for:)` now has a `default` case that routes unknown bundle IDs through `AccessibilityReader`. Existing AppleScript paths for Terminal.app and iTerm2 are unchanged.
- **AppState routing expanded**: `monitorableBundleIDs` now includes VS Code (`com.microsoft.VSCode`), Cursor (`com.todesktop.230313mzl4w4u92`), and Windsurf (`com.codeium.windsurf`). Target app lookup uses `TargetApp.allCases.first` instead of hardcoded ternary.

### Technical
- `AccessibilityReader.swift` — New service: AX permission check (always fresh, never cached), focused element reading, window tree traversal (~155 lines)
- `TerminalReader.swift` — Added `accessibilityReader` property + `default` case in `readContent(for:)` switch
- `AppState.swift` — `monitorableBundleIDs` expanded from 2 to 5 entries, improved target mapping
- `SettingsView.swift` — New "Permissions" section in Apps tab with AX status + per-app warnings
- `AccessibilityReaderTests.swift` — 15 unit tests

## [0.8.0] - 2026-02-11

### Added
- **Sound Pack Store**: Search and install game sounds directly from within VOX. Browse MyInstants for sounds (WarCraft, Mario, Zelda, etc.), preview them, and build custom sound packs — no manual file management needed.
- **SoundPackStore service**: New async service with direct HTML scraping of MyInstants.com — search results parsing, lazy MP3 URL resolution from detail pages, staging system with success/error categories, batch download with progress tracking, and URL caching.
- **SoundPackInstallerView**: Full installer UI as a sheet in Settings → TTS — search bar with suggestion chips, scrollable results with preview (▶) and category (+Success/+Error) buttons, pack builder with two-column layout, pack naming, and install button with progress bar.
- **"Browse & Install Sounds…" button**: New button in Settings → TTS → Notice Sound Pack section opens the installer sheet.
- **Copyright disclaimer**: "Sounds may be copyrighted. For personal use only." shown in installer header.
- **16 new tests**: HTML parsing (search results, MP3 URLs, deduplication, full URLs, empty HTML), staging logic (add/remove, duplicates, categories, clear), filename sanitization (special chars, truncation, whitespace), empty search handling, and MP3 extraction from search pages. Total: 58 tests (was 42).

### Technical
- `SoundPackStore.swift` — New service: HTML scraping with regex, search + staging + install + preview (~270 lines)
- `SoundPackInstallerView.swift` — New view: header, search, results list, pack builder sections (~250 lines)
- `SettingsView.swift` — TTSSettingsTab gains `soundPackStore` property, `showInstaller` state, and sheet presentation
- `AppState.swift` — Owns new `SoundPackStore` instance, passes to SettingsView
- `SoundPackStoreTests.swift` — 16 unit tests covering parsing, staging, sanitization

## [0.7.1] - 2026-02-11

### Added
- **Notice Sound Packs**: 6 built-in notice packs for the Notice verbosity level — TTS (default), WarCraft Peon ("Job's done!"), Super Mario ("Wahoo!"), Command & Conquer ("Construction complete."), Legend of Zelda ("Quest complete!"), and macOS System Sounds (Glass, Hero, Basso). Each pack has success and error phrase sets, spoken via TTS or played as system sounds.
- **Custom Sound Packs**: Drop your own `.wav`, `.mp3`, `.aif` audio files into `~/Library/Application Support/VOX/SoundPacks/[Pack Name]/success/` and `/error/` directories. VOX auto-detects custom packs and shows them in Settings. Perfect for adding your own game sounds for personal use.
- **SoundPackManager**: New `ObservableObject` service that scans the filesystem for custom sound packs, supports `.wav/.mp3/.aif/.aiff/.m4a/.caf` formats, and provides pack selection.
- **Sound Pack Settings UI**: New "Notice Sound Pack" section in Settings → TTS tab with built-in pack picker, description text, Preview button, custom packs picker (when packs are found), and "Add your own sound packs" disclosure with instructions and Open Folder / Refresh buttons.
- **5 new tests**: Notice sound pack tests for WarCraft phrases, Mario error phrases, system sounds (NSSound), TTS fallback, and custom pack scanning. Total: 42 tests (was 37).

### Changed
- **ProcessedResponse extended**: Added `soundName: String?` for macOS system sounds and `customSoundURL: URL?` for custom audio file playback.
- **ResponseProcessor pack-aware**: `.notice` verbosity now checks: (1) custom sound pack, (2) built-in game phrases via TTS, (3) macOS system sounds, (4) localized TTS notice fallback.
- **TTSEngine audio playback**: Added `playSystemSound(_:)` using `NSSound(named:)` and `playCustomSound(at:)` using `NSSound(contentsOf:byReference:)`.
- **AppState response routing**: Now routes `ProcessedResponse` to TTS speech, system sound, or custom audio based on response type.

### Technical
- `NoticeSoundPack.swift` — New file: enum with 6 cases, `CustomSoundPack` struct, `SoundPackManager` class (~130 lines)
- `SoundPackManager` injected into `ResponseProcessor` and owned by `AppState`
- `VoxSettings` gains `noticeSoundPack` and `customSoundPackName` @AppStorage properties
- Test setUp() resets sound pack settings to prevent singleton state pollution between tests

## [0.7.0] - 2026-02-11

### Added
- **OllamaService**: New HTTP client for local Ollama API — summarization, model management, server status checking, and model downloading with progress tracking. Zero external dependencies, uses native `URLSession`.
- **Terminal UI stripping**: New `stripTerminalUI()` in ResponseProcessor removes CLI artifacts before speech — progress bars (█▓░), Claude Code footer (model info, cost/token lines), keyboard hints (`(esc to cancel)`), version strings, and box-drawing characters.
- **Dutch TTS voice selection**: TTSEngine now selects the best available macOS voice matching the configured response language. Prefers premium (non-compact) voices, with automatic fallback.
- **Localized ready notices**: Notice verbosity level now speaks context-aware messages in the user's language — e.g. "Klaar. Bekijk de terminal om verder te gaan." (Dutch) or "Done. Check the terminal to continue." (English).
- **Ollama management UI**: Settings → Advanced now shows Ollama server status (green/red indicator), installed models list with sizes, model download button with progress bar, installation check with download link, and advanced configuration (URL, model name, max summary sentences).
- **Summary engine choice in onboarding**: Step 2 (TTS) now offers Heuristic vs Ollama summarization choice with Ollama status check.
- **5 new tests**: Terminal UI stripping tests for progress bars, Claude Code footer, cost lines, keyboard hints, and summary mode stripping. Total: 37 tests (was 32).

### Changed
- **Verbosity `.ping` renamed to `.notice`**: Label changed from "Ping" to "Notice", description updated to "Ready notification in your language". RawValue (1) unchanged — existing user settings preserved.
- **ResponseProcessor is now `async`**: `process()` method is async to support Ollama summarization. Falls back to heuristic when Ollama is unavailable.
- **Summary mode routes through Ollama**: When summarization method is set to Ollama, summary verbosity sends terminal output to local LLM for intelligent summarization in the user's language, with heuristic fallback.
- **Full mode now strips terminal UI**: Full verbosity output is cleaned of CLI artifacts before being read aloud.
- **Settings Advanced tab**: Expanded from basic Ollama URL/model fields to full Ollama management with status, models, download, and advanced disclosure group.

### Technical
- `OllamaService.swift` — New file: ~220 lines, `@MainActor`, `ObservableObject` with `URLSession`-based HTTP client
- `ResponseProcessor` constructor accepts optional `OllamaService` dependency
- `AppState` now owns `OllamaService` instance and injects it into `ResponseProcessor`
- `TTSEngine.preferredVoice()` uses `NSSpeechSynthesizer.availableVoices` and `attributes(forVoice:)` for language-based voice lookup
- All test methods updated to `async` for async `process()` calls

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
