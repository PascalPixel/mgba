import MGBABridge
import XCTest

final class MGBABridgeTests: XCTestCase {
    func testBundledAPURomProducesVideoAndAudioFrames() throws {
        let romURL = repositoryRoot
            .appendingPathComponent("cinema/gb/samesuite/apu/channel_1/volume/test.gb")
        XCTAssertTrue(FileManager.default.fileExists(atPath: romURL.path))

        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let saveURL = testDirectory.appendingPathComponent("game.sav")
        let stateURL = testDirectory.appendingPathComponent("slot-1.mgba-state")

        var error = [CChar](repeating: 0, count: 512)
        let core = romURL.path.withCString { romPath in
            saveURL.path.withCString { savePath in
                MGBANativeCoreCreate(romPath, savePath, &error, error.count)
            }
        }
        guard let core else {
            XCTFail("Core creation failed: \(String(cString: error))")
            return
        }
        defer { MGBANativeCoreDestroy(core) }

        XCTAssertEqual(MGBANativeCoreWidth(core), 160)
        XCTAssertEqual(MGBANativeCoreHeight(core), 144)
        XCTAssertNotNil(MGBANativeCorePixels(core))
        XCTAssertGreaterThan(MGBANativeCoreAudioSampleRate(core), 0)

        for _ in 0..<12 {
            MGBANativeCoreRunFrame(core)
        }

        var samples = [Int16](repeating: 0, count: 8192)
        let frames = samples.withUnsafeMutableBufferPointer { buffer in
            MGBANativeCoreReadAudio(core, buffer.baseAddress, buffer.count / 2)
        }
        XCTAssertGreaterThan(frames, 0)
        let peak = samples.prefix(Int(frames) * 2).map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0, "The core returned audio frames containing only silence")

        let saved = stateURL.path.withCString { path in
            MGBANativeCoreSaveState(core, path)
        }
        XCTAssertTrue(saved)
        XCTAssertGreaterThan(try Data(contentsOf: stateURL).count, 0)

        for _ in 0..<8 {
            MGBANativeCoreRunFrame(core)
        }
        let loaded = stateURL.path.withCString { path in
            MGBANativeCoreLoadState(core, path)
        }
        XCTAssertTrue(loaded)
        MGBANativeCoreRunFrame(core)
        XCTAssertNotNil(MGBANativeCorePixels(core))
    }

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
