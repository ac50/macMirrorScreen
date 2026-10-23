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

    func testLoadCorruptThrows() throws {
        let url = dir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{nope".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Config.load(from: url))
    }
}
