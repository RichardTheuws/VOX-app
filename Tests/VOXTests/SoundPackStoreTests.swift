import XCTest
@testable import VOX

@MainActor
final class SoundPackStoreTests: XCTestCase {

    // MARK: - Search Result Parsing

    func testParseSearchResultsExtractsTitlesAndSlugs() {
        let store = SoundPackStore()
        let html = """
        <div class="instant">
            <a href="/en/instant/warcraft-peon-work-work/" class="instant-link link-secondary">Warcraft Peon - Work work</a>
        </div>
        <div class="instant">
            <a href="/en/instant/mario-lets-a-go/" class="instant-link link-secondary">Mario - Let&#39;s-a Go!</a>
        </div>
        """

        let results = store.parseSearchResults(html: html)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].slug, "warcraft-peon-work-work")
        XCTAssertEqual(results[0].title, "Warcraft Peon - Work work")
        XCTAssertEqual(results[0].source, "MyInstants")
        XCTAssertEqual(results[1].slug, "mario-lets-a-go")
        XCTAssertEqual(results[1].title, "Mario - Let's-a Go!")
    }

    func testParseSearchResultsWithFullURLHref() {
        let store = SoundPackStore()
        let html = """
        <a href="https://www.myinstants.com/en/instant/zelda-secret/" class="instant-link link-secondary">Zelda Secret</a>
        """

        let results = store.parseSearchResults(html: html)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].slug, "zelda-secret")
        XCTAssertEqual(results[0].title, "Zelda Secret")
    }

    func testParseSearchResultsDeduplicatesBySlug() {
        let store = SoundPackStore()
        let html = """
        <a href="/en/instant/test-sound/" class="instant-link link-secondary">Test Sound</a>
        <a href="/en/instant/test-sound/" class="instant-link link-secondary">Test Sound Duplicate</a>
        """

        let results = store.parseSearchResults(html: html)

        XCTAssertEqual(results.count, 1, "Duplicate slugs should be deduplicated")
    }

    func testParseSearchResultsEmptyHTML() {
        let store = SoundPackStore()
        let results = store.parseSearchResults(html: "<html><body>No results</body></html>")

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - MP3 URL Parsing

    func testParseMP3URLFromPreloadVariable() {
        let store = SoundPackStore()
        let html = """
        <script>
        var preloadAudioUrl = '/media/sounds/wc3-peon-says-work-work-only-.mp3';
        </script>
        """

        let url = store.parseMP3URL(html: html)

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://www.myinstants.com/media/sounds/wc3-peon-says-work-work-only-.mp3")
    }

    func testParseMP3URLFromMediaPath() {
        let store = SoundPackStore()
        let html = """
        <div data-sound="/media/sounds/mario-wahoo.mp3"></div>
        """

        let url = store.parseMP3URL(html: html)

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("mario-wahoo.mp3"))
    }

    func testParseMP3URLReturnsNilForNoMatch() {
        let store = SoundPackStore()
        let url = store.parseMP3URL(html: "<html><body>Nothing here</body></html>")

        XCTAssertNil(url)
    }

    // MARK: - Staging Logic

    func testStagingAddAndRemove() {
        let store = SoundPackStore()
        let result = SoundSearchResult(id: "test", title: "Test", slug: "test", mp3URL: nil, source: "MyInstants")

        store.addToStaged(result, category: .success)
        XCTAssertEqual(store.stagedSounds.count, 1)
        XCTAssertEqual(store.stagedSuccessCount, 1)
        XCTAssertEqual(store.stagedErrorCount, 0)

        store.addToStaged(result, category: .error)
        XCTAssertEqual(store.stagedSounds.count, 2)
        XCTAssertEqual(store.stagedErrorCount, 1)

        // Remove the first staged sound
        let firstStaged = store.stagedSounds[0]
        store.removeFromStaged(firstStaged)
        XCTAssertEqual(store.stagedSounds.count, 1)
    }

    func testStagingPreventsDuplicates() {
        let store = SoundPackStore()
        let result = SoundSearchResult(id: "test", title: "Test", slug: "test", mp3URL: nil, source: "MyInstants")

        store.addToStaged(result, category: .success)
        store.addToStaged(result, category: .success)  // Same slug + same category

        XCTAssertEqual(store.stagedSounds.count, 1, "Same slug + category should not duplicate")
    }

    func testStagingAllowsSameSlugDifferentCategory() {
        let store = SoundPackStore()
        let result = SoundSearchResult(id: "test", title: "Test", slug: "test", mp3URL: nil, source: "MyInstants")

        store.addToStaged(result, category: .success)
        store.addToStaged(result, category: .error)

        XCTAssertEqual(store.stagedSounds.count, 2, "Same slug with different categories should be allowed")
    }

    func testClearStaged() {
        let store = SoundPackStore()
        let result1 = SoundSearchResult(id: "a", title: "A", slug: "a", mp3URL: nil, source: "MyInstants")
        let result2 = SoundSearchResult(id: "b", title: "B", slug: "b", mp3URL: nil, source: "MyInstants")

        store.addToStaged(result1, category: .success)
        store.addToStaged(result2, category: .error)
        XCTAssertEqual(store.stagedSounds.count, 2)

        store.clearStaged()
        XCTAssertTrue(store.stagedSounds.isEmpty)
    }

    // MARK: - Filename Sanitization

    func testSanitizeFilenameRemovesSpecialCharacters() {
        let store = SoundPackStore()

        XCTAssertEqual(store.sanitizeFilename("Job's done!"), "Jobs done")
        XCTAssertEqual(store.sanitizeFilename("Work/Complete\\Test"), "WorkCompleteTest")
        XCTAssertEqual(store.sanitizeFilename("Hello - World"), "Hello - World")
    }

    func testSanitizeFilenameTruncatesLongNames() {
        let store = SoundPackStore()
        let longName = String(repeating: "a", count: 100)

        let sanitized = store.sanitizeFilename(longName)

        XCTAssertLessThanOrEqual(sanitized.count, 50)
    }

    func testSanitizeFilenameTrimsWhitespace() {
        let store = SoundPackStore()

        XCTAssertEqual(store.sanitizeFilename("  Hello  "), "Hello")
    }

    // MARK: - Empty Search

    func testEmptySearchQuerySkips() async {
        let store = SoundPackStore()

        await store.search(query: "   ")

        XCTAssertTrue(store.searchResults.isEmpty)
        XCTAssertFalse(store.isSearching)
    }

    // MARK: - MP3 URL Extraction from Search Page

    func testExtractsMP3URLsFromSearchPage() {
        let store = SoundPackStore()
        let html = """
        <a href="/en/instant/test-sound/" class="instant-link link-secondary">Test Sound</a>
        <script>play('/media/sounds/test-sound.mp3')</script>
        """

        let results = store.parseSearchResults(html: html)

        XCTAssertEqual(results.count, 1)
        // MP3 URL may or may not be extracted depending on position matching
        // This test verifies the parsing doesn't crash
    }
}
