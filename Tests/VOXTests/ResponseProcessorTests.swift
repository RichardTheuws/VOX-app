import XCTest
@testable import VOX

final class ResponseProcessorTests: XCTestCase {
    private var processor: ResponseProcessor!

    override func setUp() {
        super.setUp()
        // Reset settings to defaults to avoid test pollution
        VoxSettings.shared.noticeSoundPack = .tts
        VoxSettings.shared.customSoundPackName = ""
        VoxSettings.shared.responseLanguage = .english
        processor = ResponseProcessor()
    }

    // MARK: - Silent Mode

    func testSilentModeReturnsNoText() async {
        let result = ExecutionResult(output: "some output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .silent, command: "ls", target: .terminal)
        XCTAssertNil(response.spokenText)
        XCTAssertEqual(response.status, .success)
    }

    func testSilentModeErrorStatus() async {
        let result = ExecutionResult(output: "error", exitCode: 1, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .silent, command: "ls", target: .terminal)
        XCTAssertNil(response.spokenText)
        XCTAssertEqual(response.status, .error)
    }

    // MARK: - Notice Mode

    func testNoticeModeSuccess() async {
        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .notice, command: "ls", target: .terminal)
        // Notice mode returns localized message (English default)
        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("Done") || response.spokenText!.contains("Klaar"))
        XCTAssertEqual(response.status, .success)
    }

    func testNoticeModeError() async {
        let result = ExecutionResult(output: "error", exitCode: 1, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .notice, command: "ls", target: .terminal)
        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.lowercased().contains("error") ||
                       response.spokenText!.contains("fout"))
        XCTAssertEqual(response.status, .error)
    }

    // MARK: - Summary Mode: Git Status

    func testSummaryGitStatusClean() async {
        let output = """
        On branch main
        Your branch is up to date with 'origin/main'.

        nothing to commit, working tree clean
        """
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.3, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "git status", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("main"))
        XCTAssertTrue(response.spokenText!.contains("clean"))
    }

    func testSummaryGitStatusModified() async {
        let output = """
        On branch feature
        Changes not staged for commit:
          modified:   src/app.ts
          modified:   src/utils.ts
          modified:   package.json
        """
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.3, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "git status", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("feature"))
        XCTAssertTrue(response.spokenText!.contains("3 modified"))
    }

    // MARK: - Summary Mode: Build Commands

    func testSummaryBuildSuccess() async {
        let output = "Successfully compiled 42 files."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 2.0, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "npm run build", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.lowercased().contains("success") ||
                       response.spokenText!.lowercased().contains("compiled"))
    }

    func testSummaryBuildError() async {
        let output = """
        ERROR in src/index.ts
        Module not found: Can't resolve 'react-dom'
        """
        let result = ExecutionResult(output: output, exitCode: 1, duration: 1.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "npm run build", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.lowercased().contains("error"))
    }

    // MARK: - Summary Mode: Ls

    func testSummaryLsOutput() async {
        let output = """
        total 24
        drwxr-xr-x  5 user  staff  160 Jan  1 12:00 .
        drwxr-xr-x  3 user  staff   96 Jan  1 12:00 ..
        -rw-r--r--  1 user  staff   42 Jan  1 12:00 file1.txt
        -rw-r--r--  1 user  staff   42 Jan  1 12:00 file2.txt
        """
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.1, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "ls -la", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("items listed"))
    }

    // MARK: - Summary Mode: Timeout

    func testSummaryTimeout() async {
        let result = ExecutionResult(output: "", exitCode: -1, duration: 30.0, wasTimeout: true)
        let response = await processor.process(result, verbosity: .summary, command: "sleep 999", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("timed out"))
    }

    // MARK: - Summary Mode: Empty Output

    func testSummaryEmptyOutput() async {
        let result = ExecutionResult(output: "", exitCode: 0, duration: 0.1, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "touch file.txt", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("No output"))
    }

    // MARK: - Summary Mode: Generic Error

    func testSummaryGenericError() async {
        let output = "fatal: not a git repository"
        let result = ExecutionResult(output: output, exitCode: 128, duration: 0.1, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "git log", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("128") || response.spokenText!.contains("fatal"))
    }

    // MARK: - Full Mode

    func testFullModeReturnsCleanedOutput() async {
        let output = "Hello world\nhttps://example.com/path\nDone"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .full, command: "echo test", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        // URLs should be cleaned
        XCTAssertTrue(response.spokenText!.contains("link to example.com"))
        XCTAssertFalse(response.spokenText!.contains("https://"))
    }

    func testFullModeStripsCodeBlocks() async {
        let output = "Here is code:\n```swift\nlet x = 1\n```\nEnd."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .full, command: "claude explain", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("code block omitted"))
        XCTAssertFalse(response.spokenText!.contains("let x = 1"))
    }

    // MARK: - Full Mode: Terminal UI Stripping

    func testFullModeStripsProgressBars() async {
        let output = "Building...\n█████░░░░░ 50%\nDone building."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 1.0, wasTimeout: false)
        let response = await processor.process(result, verbosity: .full, command: "build", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertFalse(response.spokenText!.contains("█"))
        XCTAssertTrue(response.spokenText!.contains("Done building"))
    }

    func testFullModeStripsClaudeCodeFooter() async {
        let output = "File created successfully.\nOpus 4.6 | project ■████ 21%\n► bypass permissions on (shift+tab to cycle)"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .full, command: "claude code", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("File created"))
        XCTAssertFalse(response.spokenText!.contains("Opus"))
        XCTAssertFalse(response.spokenText!.contains("bypass"))
    }

    func testFullModeStripsCostLines() async {
        let output = "Changes applied.\n$0.12 | 1.2k tokens"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .full, command: "claude", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("Changes applied"))
        XCTAssertFalse(response.spokenText!.contains("$0.12"))
    }

    func testFullModeStripsKeyboardHints() async {
        let output = "Ready.\n(esc to cancel)\n(shift+tab to cycle)"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await processor.process(result, verbosity: .full, command: "claude", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("Ready"))
        XCTAssertFalse(response.spokenText!.contains("esc to cancel"))
    }

    // MARK: - Summary Mode: Terminal UI Also Stripped

    func testSummaryModeAlsoStripsTerminalUI() async {
        let output = "On branch main\nnothing to commit, working tree clean\n█████████ 100%\nOpus 4.6 | done"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.3, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "git status", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("main"))
        XCTAssertFalse(response.spokenText!.contains("█"))
    }

    // MARK: - VerbosityLevel Comparable

    func testVerbosityComparable() {
        XCTAssertTrue(VerbosityLevel.silent < VerbosityLevel.notice)
        XCTAssertTrue(VerbosityLevel.notice < VerbosityLevel.summary)
        XCTAssertTrue(VerbosityLevel.summary < VerbosityLevel.full)
    }

    // MARK: - Notice Sound Packs

    func testNoticeWarCraftPhrase() async {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .warcraft
        settings.customSoundPackName = ""
        let packProcessor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await packProcessor.process(result, verbosity: .notice, command: "ls", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        let validPhrases = NoticeSoundPack.warcraft.successPhrases
        XCTAssertTrue(validPhrases.contains(response.spokenText!),
                       "Expected one of \(validPhrases), got: \(response.spokenText!)")
        XCTAssertEqual(response.status, .success)
    }

    func testNoticeMarioError() async {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .mario
        settings.customSoundPackName = ""
        let packProcessor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "error", exitCode: 1, duration: 0.5, wasTimeout: false)
        let response = await packProcessor.process(result, verbosity: .notice, command: "build", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        let validPhrases = NoticeSoundPack.mario.errorPhrases
        XCTAssertTrue(validPhrases.contains(response.spokenText!),
                       "Expected one of \(validPhrases), got: \(response.spokenText!)")
        XCTAssertEqual(response.status, .error)
    }

    func testNoticeSystemSound() async {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .systemSounds
        settings.customSoundPackName = ""
        let packProcessor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await packProcessor.process(result, verbosity: .notice, command: "ls", target: .terminal)

        // System sounds should return soundName, not spokenText
        XCTAssertNil(response.spokenText)
        XCTAssertNotNil(response.soundName)
        XCTAssertTrue(NoticeSoundPack.successSounds.contains(response.soundName!),
                       "Expected one of \(NoticeSoundPack.successSounds), got: \(response.soundName!)")
        XCTAssertEqual(response.status, .success)
    }

    func testNoticeTTSFallback() async {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .tts
        settings.customSoundPackName = ""
        let packProcessor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await packProcessor.process(result, verbosity: .notice, command: "ls", target: .terminal)

        // TTS pack should return localized notice, same as before
        XCTAssertNotNil(response.spokenText)
        XCTAssertNil(response.soundName)
        XCTAssertNil(response.customSoundURL)
        XCTAssertTrue(response.spokenText!.contains("Done") || response.spokenText!.contains("Klaar"))
    }

    // MARK: - Smart Summarization Bypass

    func testSmartSummarizationSkipsShortOutput() async {
        // Short output (≤2 sentences) should be read directly, not routed to Ollama
        let output = "Build succeeded. 42 tests passed."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 1.0, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "swift test", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        // Short output should be returned cleaned, not summarized
        XCTAssertTrue(response.spokenText!.contains("Build succeeded"))
        XCTAssertTrue(response.spokenText!.contains("42 tests"))
        XCTAssertEqual(response.status, .success)
    }

    func testSmartSummarizationShortSingleSentence() async {
        let output = "Done."
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.1, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "touch file", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("Done"))
    }

    func testSmartSummarizationLongOutputUsesHeuristic() async {
        // Long output (many sentences) should go through summarization, not direct readback
        let lines = (1...20).map { "Line \($0) of output with some content here." }
        let output = lines.joined(separator: "\n")
        let result = ExecutionResult(output: output, exitCode: 0, duration: 1.0, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "cat bigfile", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        // Should be summarized (heuristic fallback since no Ollama)
        // The heuristic returns first line + count — much shorter than full output
        XCTAssertTrue(response.spokenText!.count < output.count)
    }

    func testSmartSummarizationCharCountThreshold() async {
        // Under 150 chars should be read directly
        let output = "File created at /tmp/test.txt"
        let result = ExecutionResult(output: output, exitCode: 0, duration: 0.1, wasTimeout: false)
        let response = await processor.process(result, verbosity: .summary, command: "touch test", target: .terminal)

        XCTAssertNotNil(response.spokenText)
        XCTAssertTrue(response.spokenText!.contains("File created"))
    }

    // MARK: - TTS Engine Type

    func testTTSEngineTypeAllCases() {
        XCTAssertEqual(TTSEngineType.allCases.count, 6)
        XCTAssertTrue(TTSEngineType.allCases.contains(.edgeTTS))
        XCTAssertTrue(TTSEngineType.allCases.contains(.elevenLabs))
    }

    func testEdgeTTSDefaultVoice() {
        let settings = VoxSettings.shared
        XCTAssertEqual(settings.edgeTTSVoice, "nl-NL-ColetteNeural")
    }

    @MainActor func testEdgeTTSBinarySearch() {
        // Should not crash, returns nil or valid path
        let path = TTSEngine.findEdgeTTSBinary()
        if let path = path {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }
        // isEdgeTTSInstalled should match
        XCTAssertEqual(TTSEngine.isEdgeTTSInstalled, path != nil)
    }

    func testCustomSoundPackScanning() {
        let manager = SoundPackManager()

        // Ensure the directory exists
        let dir = SoundPackManager.soundPacksDirectory
        XCTAssertNotNil(dir)

        // Scan should not crash even with empty directory
        manager.scanForPacks()

        // Verify scanning doesn't crash and returns empty or valid packs
        XCTAssertNotNil(manager.customPacks)
    }

    // MARK: - Per-App Sound Pack Selection

    func testPerAppSoundPackDefault() {
        // Without per-app setting → should fallback to global
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .warcraft

        // Clear any per-app setting
        UserDefaults.standard.removeObject(forKey: "soundPack_Cursor")

        XCTAssertEqual(settings.soundPack(for: .cursor), .warcraft)
    }

    func testPerAppSoundPackSet() {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .tts  // Global is TTS

        // Set per-app to Mario for Cursor
        settings.setSoundPack(.mario, for: .cursor)

        XCTAssertEqual(settings.soundPack(for: .cursor), .mario)

        // Other apps should still use global
        UserDefaults.standard.removeObject(forKey: "soundPack_Terminal")
        XCTAssertEqual(settings.soundPack(for: .terminal), .tts)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "soundPack_Cursor")
    }

    func testPerAppCustomSoundPackDefault() {
        let settings = VoxSettings.shared
        settings.customSoundPackName = "GlobalPack"

        // Clear per-app setting
        UserDefaults.standard.removeObject(forKey: "customSoundPack_VS Code")

        XCTAssertEqual(settings.customSoundPackName(for: .vsCode), "GlobalPack")
    }

    func testPerAppCustomSoundPackSet() {
        let settings = VoxSettings.shared
        settings.customSoundPackName = "GlobalPack"

        // Set per-app custom pack
        settings.setCustomSoundPackName("CursorPack", for: .cursor)

        XCTAssertEqual(settings.customSoundPackName(for: .cursor), "CursorPack")

        // Other apps still fallback to global
        UserDefaults.standard.removeObject(forKey: "customSoundPack_Terminal")
        XCTAssertEqual(settings.customSoundPackName(for: .terminal), "GlobalPack")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "customSoundPack_Cursor")
    }

    func testPerAppSoundPackInNoticeMode() async {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .tts         // Global: TTS
        settings.customSoundPackName = ""
        settings.setSoundPack(.warcraft, for: .cursor)  // Per-app: WarCraft for Cursor
        let packProcessor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)

        // Cursor should use WarCraft
        let cursorResponse = await packProcessor.process(result, verbosity: .notice, command: "build", target: .cursor)
        XCTAssertNotNil(cursorResponse.spokenText)
        let validPhrases = NoticeSoundPack.warcraft.successPhrases
        XCTAssertTrue(validPhrases.contains(cursorResponse.spokenText!),
                       "Expected WarCraft phrase, got: \(cursorResponse.spokenText!)")

        // Terminal should use global TTS
        UserDefaults.standard.removeObject(forKey: "soundPack_Terminal")
        let terminalResponse = await packProcessor.process(result, verbosity: .notice, command: "ls", target: .terminal)
        XCTAssertNotNil(terminalResponse.spokenText)
        XCTAssertTrue(terminalResponse.spokenText!.contains("Done") || terminalResponse.spokenText!.contains("Klaar"))

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "soundPack_Cursor")
    }

    func testPerAppSoundPackClaudeDesktop() async {
        let settings = VoxSettings.shared
        settings.noticeSoundPack = .tts
        settings.customSoundPackName = ""
        settings.setSoundPack(.zelda, for: .claudeDesktop)
        let packProcessor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "output", exitCode: 0, duration: 0.5, wasTimeout: false)
        let response = await packProcessor.process(result, verbosity: .notice, command: "ask", target: .claudeDesktop)

        XCTAssertNotNil(response.spokenText)
        let validPhrases = NoticeSoundPack.zelda.successPhrases
        XCTAssertTrue(validPhrases.contains(response.spokenText!),
                       "Expected Zelda phrase, got: \(response.spokenText!)")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "soundPack_Claude Desktop")
    }
}
