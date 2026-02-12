import XCTest
@testable import VOX

final class LanguageDetectorTests: XCTestCase {

    func testDetectDutch() {
        let result = LanguageDetector.detect("Dit is een test in het Nederlands om te kijken of de taalherkenning goed werkt.")
        XCTAssertEqual(result, "nl")
    }

    func testDetectEnglish() {
        let result = LanguageDetector.detect("This is a test in English to verify the language detection works correctly.")
        XCTAssertEqual(result, "en")
    }

    func testDetectGerman() {
        let result = LanguageDetector.detect("Dies ist ein Test auf Deutsch um die Spracherkennung zu überprüfen.")
        XCTAssertEqual(result, "de")
    }

    func testFallbackEnglish() {
        // Very short or ambiguous text should fall back to English
        let result = LanguageDetector.detect("OK")
        XCTAssertEqual(result, "en")
    }
}

final class AdaptiveEdgeTTSVoiceTests: XCTestCase {

    override func tearDown() {
        // Reset to defaults to avoid test pollution
        VoxSettings.shared.voiceGender = .female
        super.tearDown()
    }

    @MainActor func testDutchFemale() {
        let settings = VoxSettings.shared
        settings.voiceGender = .female
        let engine = TTSEngine(settings: settings)
        let voice = engine.adaptiveEdgeTTSVoice(for: "Dit is een test in het Nederlands om te kijken of de stem klopt.")
        XCTAssertEqual(voice, "nl-NL-ColetteNeural")
    }

    @MainActor func testDutchMale() {
        let settings = VoxSettings.shared
        settings.voiceGender = .male
        let engine = TTSEngine(settings: settings)
        let voice = engine.adaptiveEdgeTTSVoice(for: "Dit is een test in het Nederlands om te kijken of de stem klopt.")
        XCTAssertEqual(voice, "nl-NL-MaartenNeural")
    }

    @MainActor func testEnglishFemale() {
        let settings = VoxSettings.shared
        settings.voiceGender = .female
        let engine = TTSEngine(settings: settings)
        let voice = engine.adaptiveEdgeTTSVoice(for: "This is a test in English to verify the voice selection works correctly.")
        XCTAssertEqual(voice, "en-US-JennyNeural")
    }

    @MainActor func testGermanMale() {
        let settings = VoxSettings.shared
        settings.voiceGender = .male
        let engine = TTSEngine(settings: settings)
        let voice = engine.adaptiveEdgeTTSVoice(for: "Dies ist ein Test auf Deutsch um die Sprachauswahl zu überprüfen.")
        XCTAssertEqual(voice, "de-DE-ConradNeural")
    }
}

final class LocalizedSummaryTests: XCTestCase {

    func testLocalizedSummaryDutch() {
        let settings = VoxSettings.shared
        settings.responseLanguage = .dutch
        let processor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "", exitCode: 0, duration: 0.1, wasTimeout: false)
        let summary = processor.summarize(result, command: "touch file.txt")

        XCTAssertTrue(summary.contains("Klaar"), "Expected Dutch 'Klaar', got: \(summary)")
    }

    func testLocalizedSummaryGerman() {
        let settings = VoxSettings.shared
        settings.responseLanguage = .german
        let processor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "", exitCode: 0, duration: 0.1, wasTimeout: false)
        let summary = processor.summarize(result, command: "touch file.txt")

        XCTAssertTrue(summary.contains("Fertig"), "Expected German 'Fertig', got: \(summary)")
    }

    func testLocalizedSummaryEnglish() {
        let settings = VoxSettings.shared
        settings.responseLanguage = .english
        let processor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "", exitCode: 0, duration: 0.1, wasTimeout: false)
        let summary = processor.summarize(result, command: "touch file.txt")

        XCTAssertTrue(summary.contains("Done"), "Expected English 'Done', got: \(summary)")
    }

    func testLocalizedTimeoutDutch() {
        let settings = VoxSettings.shared
        settings.responseLanguage = .dutch
        let processor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "", exitCode: -1, duration: 30.0, wasTimeout: true)
        let summary = processor.summarize(result, command: "sleep 999")

        XCTAssertTrue(summary.contains("verlopen"), "Expected Dutch 'verlopen', got: \(summary)")
    }

    func testLocalizedErrorGerman() {
        let settings = VoxSettings.shared
        settings.responseLanguage = .german
        let processor = ResponseProcessor(settings: settings)

        let result = ExecutionResult(output: "fatal: not a git repo", exitCode: 128, duration: 0.1, wasTimeout: false)
        let summary = processor.summarize(result, command: "git log")

        XCTAssertTrue(summary.contains("Fehler"), "Expected German 'Fehler', got: \(summary)")
    }
}

final class VoiceGenderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to defaults to avoid test pollution from @AppStorage
        VoxSettings.shared.voiceGender = .female
        VoxSettings.shared.responseLanguage = .english
    }

    func testVoiceGenderDefault() {
        // Verify the enum default value
        let fresh = VoiceGender.female
        XCTAssertEqual(fresh.rawValue, "Female")
    }

    func testResponseLanguageGerman() {
        // Verify German case exists in ResponseLanguage
        XCTAssertNotNil(ResponseLanguage.german)
        XCTAssertEqual(ResponseLanguage.german.rawValue, "Deutsch")
    }

    func testVoiceGenderAllCases() {
        XCTAssertEqual(VoiceGender.allCases.count, 2)
        XCTAssertTrue(VoiceGender.allCases.contains(.female))
        XCTAssertTrue(VoiceGender.allCases.contains(.male))
    }

    func testEffectiveLanguageCodeGerman() {
        let settings = VoxSettings.shared
        settings.responseLanguage = .german
        let processor = ResponseProcessor(settings: settings)

        XCTAssertEqual(processor.effectiveLanguageCode(), "de")
    }
}
