import XCTest
@testable import MirrorCore

final class ConfigTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MirrorCoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testKeyFormat() {
        XCTAssertEqual(Config.key(vendor: 4268, model: 41187, serial: 0), "4268-41187-0")
    }

    func testLoadMissingReturnsEmpty() throws {
        let config = try Config.load(from: dir.appendingPathComponent("missing.json"))
        XCTAssertEqual(config, Config())
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = dir.appendingPathComponent("nested/config.json")
        var config = Config()
        config.displays["4268-41187-0"] = DisplayEntry(name: "DELL U2723QE", mode: .mirror)
        try config.save(to: url)
        XCTAssertEqual(try Config.load(from: url), config)
    }

    func testDimStateRoundTripAndRemoval() throws {
        let url = DimState.url(besideConfig: dir.appendingPathComponent("config.json"))
        XCTAssertNil(DimState.load(from: url))
        try DimState.save(0.8, to: url)
        XCTAssertEqual(DimState.load(from: url), 0.8)
        try DimState.save(nil, to: url)
        XCTAssertNil(DimState.load(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoadCorruptThrows() throws {
        let url = dir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{nope".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Config.load(from: url))
    }
}
