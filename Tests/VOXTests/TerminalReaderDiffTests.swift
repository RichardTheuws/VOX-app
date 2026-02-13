import XCTest
@testable import VOX

final class TerminalReaderDiffTests: XCTestCase {
    private var reader: TerminalReader!

    override func setUp() {
        super.setUp()
        reader = TerminalReader()
    }

    // MARK: - AX Content Diff (set-based)

    func testExtractAXNewContentFindsNewLines() {
        let before = """
        function hello() {
            console.log("hello");
        }
        """
        let after = """
        function hello() {
            console.log("hello");
        }
        // AI response: Added error handling
        function hello() {
            try {
                console.log("hello");
            } catch(e) {
                console.error(e);
            }
        }
        """
        let result = reader.extractNewContent(before: before, after: after, isTerminalBased: false)

        // Should find genuinely new lines
        XCTAssertTrue(result.contains("AI response"))
        XCTAssertTrue(result.contains("try"))
        XCTAssertTrue(result.contains("catch"))
    }

    func testExtractAXNewContentReturnsFullOnCompleteChange() {
        let before = "Loading editor..."
        let after = "File saved successfully.\nAll tests passing."

        let result = reader.extractNewContent(before: before, after: after, isTerminalBased: false)

        // Completely different content → should return new content
        XCTAssertTrue(result.contains("File saved"))
        XCTAssertTrue(result.contains("tests passing"))
    }

    func testExtractAXNoChangeReturnsEmpty() {
        let content = "function hello() { console.log('hi'); }"
        let result = reader.extractNewContent(before: content, after: content, isTerminalBased: false)

        XCTAssertEqual(result, "")
    }

    func testExtractAXContentHandlesInPlaceChange() {
        // Simulates AX content where existing lines change (not append)
        let before = """
        Status: Running
        Progress: 50%
        """
        let after = """
        Status: Complete
        Progress: 100%
        Result: Success
        """
        let result = reader.extractNewContent(before: before, after: after, isTerminalBased: false)

        // Should find changed/new lines
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("Complete") || result.contains("100%") || result.contains("Success"))
    }

    // MARK: - Terminal Content Diff (line-append)

    func testExtractTerminalNewLinesAppended() {
        let before = "$ git status\nOn branch main"
        let after = "$ git status\nOn branch main\nnothing to commit, working tree clean\n$"

        let result = reader.extractNewContent(before: before, after: after, isTerminalBased: true)

        XCTAssertTrue(result.contains("nothing to commit"))
    }

    func testExtractTerminalContentUnchanged() {
        let content = "$ ls\nfile1.txt\nfile2.txt"
        let result = reader.extractNewContent(before: content, after: content, isTerminalBased: true)

        XCTAssertEqual(result, "")
    }

    func testExtractTerminalContentGrowsOnExistingLine() {
        let before = "Downloading..."
        let after = "Downloading... 100% complete"

        let result = reader.extractNewContent(before: before, after: after, isTerminalBased: true)

        // Content grew on existing line
        XCTAssertTrue(result.contains("100%") || result.contains("complete"))
    }

    // MARK: - Edge Cases

    func testEmptyBeforeAndAfter() {
        let result = reader.extractNewContent(before: "", after: "", isTerminalBased: false)
        XCTAssertEqual(result, "")
    }

    func testEmptyBeforeWithNewContent() {
        let result = reader.extractNewContent(before: "", after: "Hello world", isTerminalBased: false)
        XCTAssertTrue(result.contains("Hello world"))
    }

    // MARK: - Adaptive Poll Interval

    func testAdaptivePollIntervalActive() {
        // Content just changed → fast polling
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 0), 0.5)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 1.0), 0.5)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 2.9), 0.5)
    }

    func testAdaptivePollIntervalFirstPause() {
        // 3-8 seconds since last change → slow down
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 3.0), 2.0)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 5.0), 2.0)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 7.9), 2.0)
    }

    func testAdaptivePollIntervalLongerPause() {
        // 8-15 seconds → slower
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 8.0), 5.0)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 12.0), 5.0)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 14.9), 5.0)
    }

    func testAdaptivePollIntervalWaiting() {
        // 15+ seconds → minimal polling
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 15.0), 10.0)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 60.0), 10.0)
        XCTAssertEqual(TerminalReader.adaptivePollInterval(secondsSinceLastChange: 300.0), 10.0)
    }

    // MARK: - Shell Prompt Detection

    func testShellPromptDetectionBash() {
        // Bash default prompt: ends with $
        XCTAssertTrue(reader.endsWithShellPrompt("user@host:~$ "))
        XCTAssertTrue(reader.endsWithShellPrompt("some output\nuser@macbook:~/project$ "))
        XCTAssertTrue(reader.endsWithShellPrompt("richardtheuws@MacBook-Air ~ %\nrichardtheuws@MacBook-Air ~ $"))
    }

    func testShellPromptDetectionZsh() {
        // Zsh default prompt: ends with %
        XCTAssertTrue(reader.endsWithShellPrompt("user@host ~ % "))
        XCTAssertTrue(reader.endsWithShellPrompt("some output\nrichardtheuws@MacBook-Air ~ %"))
    }

    func testShellPromptDetectionStarship() {
        // Starship prompt: ends with ❯
        XCTAssertTrue(reader.endsWithShellPrompt("~/projects/vox\n❯"))
        XCTAssertTrue(reader.endsWithShellPrompt("some output\n❯ "))
    }

    func testShellPromptDetectionRoot() {
        // Root prompt: ends with #
        XCTAssertTrue(reader.endsWithShellPrompt("root@server:/var/log# "))
    }

    func testShellPromptDetectionNotPrompt() {
        // Regular output should NOT be detected as prompt
        XCTAssertFalse(reader.endsWithShellPrompt("Building project..."))
        XCTAssertFalse(reader.endsWithShellPrompt("Compiling Swift sources"))
        XCTAssertFalse(reader.endsWithShellPrompt("100% complete"))
        XCTAssertFalse(reader.endsWithShellPrompt(""))
    }

    func testShellPromptDetectionLongLineNotPrompt() {
        // Very long lines (>200 chars) should not be considered prompts
        let longLine = String(repeating: "a", count: 250) + " $"
        XCTAssertFalse(reader.endsWithShellPrompt(longLine))
    }

    func testShellPromptDetectionMultilineContent() {
        // Should check only the last non-empty line
        let content = """
        $ claude "fix the bug"
        I'll analyze the code and fix the bug.

        Created file: src/fix.swift
        Modified file: src/main.swift

        richardtheuws@MacBook-Air ~/Documents/VOX-app %
        """
        XCTAssertTrue(reader.endsWithShellPrompt(content))
    }

    func testShellPromptDetectionTrailingEmptyLines() {
        // Should skip trailing empty lines and find prompt
        let content = "some output\nuser@host:~$ \n\n\n"
        XCTAssertTrue(reader.endsWithShellPrompt(content))
    }
}
