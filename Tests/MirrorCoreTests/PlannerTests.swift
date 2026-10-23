import XCTest
@testable import MirrorCore

final class PlannerTests: XCTestCase {
    private let builtinID: UInt32 = 1
    private let extKey = "4268-41187-0"

    private func builtin(mirrors: UInt32 = 0) -> Display {
        Display(id: builtinID, isBuiltin: true, key: "1552-41000-0", name: "Built-in", mirrorsDisplayID: mirrors)
    }

    private func ext(_ id: UInt32 = 2, key: String? = nil) -> Display {
        Display(id: id, isBuiltin: false, key: key ?? extKey, name: "DELL", mirrorsDisplayID: 0)
    }

    private func config(_ mode: Mode?, key: String? = nil) -> Config {
        guard let mode else { return Config() }
        return Config(displays: [key ?? extKey: DisplayEntry(name: "DELL", mode: mode)])
    }

    func testUnknownExternalIsRemembered() {
        let actions = plan(displays: [builtin(), ext()], config: config(nil), dimmed: false)
        XCTAssertEqual(actions, [.remember(key: extKey, name: "DELL")])
    }

    func testMirrorModeNotMirroredEmitsMirrorThenDim() {
        let actions = plan(displays: [builtin(), ext()], config: config(.mirror), dimmed: false)
        XCTAssertEqual(actions, [.mirror(builtin: builtinID, master: 2), .dim(builtin: builtinID)])
    }

    func testAlreadyMirroredEmitsDimOnly() {
        let actions = plan(displays: [builtin(mirrors: 2), ext()], config: config(.mirror), dimmed: false)
        XCTAssertEqual(actions, [.dim(builtin: builtinID)])
    }

    func testMirroredAndDimmedIsNoop() {
        let actions = plan(displays: [builtin(mirrors: 2), ext()], config: config(.mirror), dimmed: true)
        XCTAssertEqual(actions, [])
    }

    func testNoExternalDimmedRestores() {
        let actions = plan(displays: [builtin()], config: config(.mirror), dimmed: true)
        XCTAssertEqual(actions, [.restore(builtin: builtinID)])
    }

    func testNoExternalNotDimmedIsNoop() {
        XCTAssertEqual(plan(displays: [builtin()], config: config(.mirror), dimmed: false), [])
    }

    func testNoneModeDimmedRestores() {
        let actions = plan(displays: [builtin(), ext()], config: config(Mode.none), dimmed: true)
        XCTAssertEqual(actions, [.restore(builtin: builtinID)])
    }

    func testNoBuiltinNoActions() {
        XCTAssertEqual(plan(displays: [ext()], config: config(.mirror), dimmed: true), [])
    }

    func testFirstMirrorModeExternalWins() {
        var cfg = config(Mode.none, key: "a")
        cfg.displays["b"] = DisplayEntry(name: "B", mode: .mirror)
        let actions = plan(displays: [builtin(), ext(2, key: "a"), ext(3, key: "b")], config: cfg, dimmed: false)
        XCTAssertEqual(actions, [.mirror(builtin: builtinID, master: 3), .dim(builtin: builtinID)])
    }

    func testMaintainRestoresWhenNoLongerMirrored() {
        XCTAssertEqual(maintain(displays: [builtin(), ext()], brightness: 0), .restore(builtin: builtinID))
        XCTAssertEqual(maintain(displays: [builtin()], brightness: 0), .restore(builtin: builtinID))
    }

    func testMaintainRedimsWhenBacklightCameBackWhileMirrored() {
        XCTAssertEqual(maintain(displays: [builtin(mirrors: 2), ext()], brightness: 0.35), .dim(builtin: builtinID))
    }

    func testMaintainIsNoopWhileMirroredAndDark() {
        XCTAssertNil(maintain(displays: [builtin(mirrors: 2), ext()], brightness: 0))
        XCTAssertNil(maintain(displays: [builtin(mirrors: 2), ext()], brightness: nil))
    }

    func testMaintainWithoutBuiltinIsNoop() {
        XCTAssertNil(maintain(displays: [ext()], brightness: 0.5))
    }

    func testRestoreFloorsAtPointThree() {
        XCTAssertEqual(restoreValue(saved: nil), 0.3)
        XCTAssertEqual(restoreValue(saved: 0), 0.3)
        XCTAssertEqual(restoreValue(saved: 0.8), 0.8)
    }
}
