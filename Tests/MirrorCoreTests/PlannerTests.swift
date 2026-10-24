import XCTest
@testable import MirrorCore

final class PlannerTests: XCTestCase {
    private let builtinID: UInt32 = 1
    private let extKey = "4268-41187-0"

    private func builtin(mirrors: UInt32 = 0) -> Display {
        Display(id: builtinID, isBuiltin: true, key: "1552-41000-0", name: "Built-in", mirrorsDisplayID: mirrors)
    }

    /// `mirrors: builtinID` is the wanted arrangement: the external shows the panel's picture.
    private func ext(_ id: UInt32 = 2, key: String? = nil, mirrors: UInt32 = 0) -> Display {
        Display(id: id, isBuiltin: false, key: key ?? extKey, name: "DELL", mirrorsDisplayID: mirrors)
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
        XCTAssertEqual(actions, [.mirror(external: 2, builtin: builtinID), .dim(builtin: builtinID)])
    }

    func testAlreadyMirroredEmitsDimOnly() {
        let actions = plan(displays: [builtin(), ext(mirrors: builtinID)], config: config(.mirror), dimmed: false)
        XCTAssertEqual(actions, [.dim(builtin: builtinID)])
    }

    func testMirroredAndDimmedIsNoop() {
        let actions = plan(displays: [builtin(), ext(mirrors: builtinID)], config: config(.mirror), dimmed: true)
        XCTAssertEqual(actions, [])
    }

    /// v0 made the panel a mirror of the external, which turns the external into the main display.
    /// That arrangement is the wrong way round: it is re-arranged, never accepted as "already mirrored".
    func testPanelMirroringExternalIsRearranged() {
        let v0 = [builtin(mirrors: 2), ext()]
        XCTAssertEqual(plan(displays: v0, config: config(.mirror), dimmed: false),
                       [.mirror(external: 2, builtin: builtinID), .dim(builtin: builtinID)])
        XCTAssertEqual(plan(displays: v0, config: config(.mirror), dimmed: true),
                       [.mirror(external: 2, builtin: builtinID)])
    }

    func testNoExternalDimmedRestores() {
        let actions = plan(displays: [builtin()], config: config(.mirror), dimmed: true)
        XCTAssertEqual(actions, [.restore(builtin: builtinID)])
    }

    func testNoExternalNotDimmedIsNoop() {
        XCTAssertEqual(plan(displays: [builtin()], config: config(.mirror), dimmed: false), [])
    }

    /// Mode none never re-arranges anything; the menu's "Do nothing" releases the mirror itself.
    func testNoneModeDimmedRestores() {
        for displays in [[builtin(), ext()], [builtin(), ext(mirrors: builtinID)], [builtin(mirrors: 2), ext()]] {
            XCTAssertEqual(plan(displays: displays, config: config(Mode.none), dimmed: true),
                           [.restore(builtin: builtinID)])
        }
    }

    func testNoBuiltinNoActions() {
        XCTAssertEqual(plan(displays: [ext()], config: config(.mirror), dimmed: true), [])
    }

    func testMirrorModeExternalIsChosenOverNoneMode() {
        var cfg = config(Mode.none, key: "a")
        cfg.displays["b"] = DisplayEntry(name: "B", mode: .mirror)
        let actions = plan(displays: [builtin(), ext(2, key: "a"), ext(3, key: "b")], config: cfg, dimmed: false)
        XCTAssertEqual(actions, [.mirror(external: 3, builtin: builtinID), .dim(builtin: builtinID)])
    }

    func testFirstOfTwoMirrorModeExternalsWins() {
        var cfg = config(.mirror, key: "a")
        cfg.displays["b"] = DisplayEntry(name: "B", mode: .mirror)
        XCTAssertEqual(plan(displays: [builtin(), ext(2, key: "a"), ext(3, key: "b")], config: cfg, dimmed: false),
                       [.mirror(external: 2, builtin: builtinID), .dim(builtin: builtinID)])
    }

    /// The controller saves remembered entries even when the mirror after them fails.
    func testRememberPrecedesMirrorAndDim() {
        let actions = plan(displays: [builtin(), ext(2, key: "new"), ext(3)], config: config(.mirror), dimmed: false)
        XCTAssertEqual(actions, [.remember(key: "new", name: "DELL"),
                                 .mirror(external: 3, builtin: builtinID),
                                 .dim(builtin: builtinID)])
    }

    /// It is the mirror-mode external that has to mirror the panel, not just any external.
    func testPlanChecksTheChosenExternalNotJustAnyMirror() {
        var cfg = config(Mode.none, key: "a")
        cfg.displays["b"] = DisplayEntry(name: "B", mode: .mirror)
        XCTAssertEqual(plan(displays: [builtin(), ext(2, key: "a"), ext(3, key: "b", mirrors: builtinID)],
                            config: cfg, dimmed: false),
                       [.dim(builtin: builtinID)])
        XCTAssertEqual(plan(displays: [builtin(), ext(2, key: "a", mirrors: builtinID), ext(3, key: "b")],
                            config: cfg, dimmed: false),
                       [.mirror(external: 3, builtin: builtinID), .dim(builtin: builtinID)])
    }

    func testBuiltinIsMirroredOnlyByAnOnlineExternal() {
        XCTAssertTrue(builtinIsMirrored([builtin(), ext(mirrors: builtinID)]))
        XCTAssertTrue(builtinIsMirrored([builtin(), ext(2), ext(3, mirrors: builtinID)]))
        XCTAssertFalse(builtinIsMirrored([builtin(), ext()]))
        XCTAssertFalse(builtinIsMirrored([builtin(mirrors: 2), ext()]))  // the v0 arrangement
        XCTAssertFalse(builtinIsMirrored([builtin(), ext(2, mirrors: 3), ext(3)]))  // externals mirroring each other
        XCTAssertFalse(builtinIsMirrored([builtin()]))
        XCTAssertFalse(builtinIsMirrored([ext(mirrors: builtinID)]))  // panel offline
    }

    /// Restoring wins over re-dimming whatever the brightness: a panel that no external mirrors must light up.
    func testMaintainRestoresWhenNoLongerMirrored() {
        let brightnesses: [Float?] = [0, 0.35, nil]
        for brightness in brightnesses {
            XCTAssertEqual(maintain(displays: [builtin(), ext()], brightness: brightness), .restore(builtin: builtinID))
            XCTAssertEqual(maintain(displays: [builtin()], brightness: brightness), .restore(builtin: builtinID))
            XCTAssertEqual(maintain(displays: [builtin(mirrors: 2), ext()], brightness: brightness),
                           .restore(builtin: builtinID))
        }
    }

    func testMaintainRedimsWhenBacklightCameBackWhileMirrored() {
        XCTAssertEqual(maintain(displays: [builtin(), ext(mirrors: builtinID)], brightness: 0.35),
                       .dim(builtin: builtinID))
    }

    func testMaintainIsNoopWhileMirroredAndDark() {
        XCTAssertNil(maintain(displays: [builtin(), ext(mirrors: builtinID)], brightness: 0))
        XCTAssertNil(maintain(displays: [builtin(), ext(mirrors: builtinID)], brightness: nil))
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
