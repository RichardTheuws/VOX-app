import NaturalLanguage

/// Detects language of text for adaptive voice selection.
/// Uses Apple's NLLanguageRecognizer constrained to supported languages (NL/EN/DE).
enum LanguageDetector {
    /// Detect primary language of text. Returns "nl", "en", or "de".
    /// Falls back to "en" for unrecognized or ambiguous text.
    static func detect(_ text: String) -> String {
        // Very short text is unreliable for language detection — default to English
        guard text.count >= 10 else { return "en" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        // Constrain to supported languages for better accuracy on short text
        recognizer.languageConstraints = [.dutch, .english, .german]

        guard let language = recognizer.dominantLanguage else { return "en" }

        switch language {
        case .dutch: return "nl"
        case .german: return "de"
        default: return "en"
        }
    }
}
