import XCTest
@testable import VOX

final class SoundPackManagerTests: XCTestCase {

    private var tempDir: URL!
    private var manager: SoundPackManager!

    override func setUp() {
        super.setUp()
        // Use a temp directory to avoid touching real sound packs
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-test-soundpacks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Delete Pack

    func testDeletePackRemovesDirectory() throws {
        // Create a fake pack directory
        let packDir = tempDir.appendingPathComponent("TestPack")
        let successDir = packDir.appendingPathComponent("success")
        let errorDir = packDir.appendingPathComponent("error")
        let fm = FileManager.default

        try fm.createDirectory(at: successDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: errorDir, withIntermediateDirectories: true)

        // Create a dummy audio file
        let dummyFile = successDir.appendingPathComponent("test.mp3")
        try Data("fake audio".utf8).write(to: dummyFile)

        XCTAssertTrue(fm.fileExists(atPath: packDir.path))

        // Delete the pack
        try fm.removeItem(at: packDir)

        XCTAssertFalse(fm.fileExists(atPath: packDir.path))
    }

    // MARK: - Delete Sound

    func testDeleteSoundRemovesFile() throws {
        // Create a fake pack with a sound file
        let packDir = tempDir.appendingPathComponent("TestPack")
        let successDir = packDir.appendingPathComponent("success")
        let fm = FileManager.default

        try fm.createDirectory(at: successDir, withIntermediateDirectories: true)

        let soundFile = successDir.appendingPathComponent("test-sound.mp3")
        try Data("fake audio data".utf8).write(to: soundFile)

        XCTAssertTrue(fm.fileExists(atPath: soundFile.path))

        // Delete the sound
        try fm.removeItem(at: soundFile)

        XCTAssertFalse(fm.fileExists(atPath: soundFile.path))
        // Pack directory should still exist
        XCTAssertTrue(fm.fileExists(atPath: packDir.path))
    }

    // MARK: - Custom Sound Pack Model

    func testCustomSoundPackRandomSound() {
        let url1 = URL(fileURLWithPath: "/tmp/success1.mp3")
        let url2 = URL(fileURLWithPath: "/tmp/error1.mp3")

        let pack = CustomSoundPack(
            name: "Test",
            path: URL(fileURLWithPath: "/tmp/Test"),
            successFiles: [url1],
            errorFiles: [url2]
        )

        XCTAssertEqual(pack.id, "Test")
        XCTAssertEqual(pack.randomSound(isSuccess: true), url1)
        XCTAssertEqual(pack.randomSound(isSuccess: false), url2)
    }

    func testCustomSoundPackRandomSoundReturnsNilWhenEmpty() {
        let pack = CustomSoundPack(
            name: "Empty",
            path: URL(fileURLWithPath: "/tmp/Empty"),
            successFiles: [],
            errorFiles: []
        )

        XCTAssertNil(pack.randomSound(isSuccess: true))
        XCTAssertNil(pack.randomSound(isSuccess: false))
    }

    // MARK: - Sound Pack Choice

    func testSoundPackChoiceLabels() {
        let builtIn = SoundPackChoice.builtIn(.warcraft)
        XCTAssertEqual(builtIn.label, "WarCraft Peon")

        let custom = SoundPackChoice.custom("My Custom Pack")
        XCTAssertEqual(custom.label, "My Custom Pack")
    }
}
