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
}
