import Foundation

/// A snapshot of one online display, as the planner sees it.
public struct Display: Equatable {
    public var id: UInt32
    public var isBuiltin: Bool
    public var key: String
    public var name: String
    /// The display this one mirrors, or 0 when it is not a mirror of anything.
    public var mirrorsDisplayID: UInt32

    public init(id: UInt32, isBuiltin: Bool, key: String, name: String, mirrorsDisplayID: UInt32) {
        self.id = id
        self.isBuiltin = isBuiltin
        self.key = key
        self.name = name
        self.mirrorsDisplayID = mirrorsDisplayID
    }
}

public enum Action: Equatable {
    /// An external display not yet in the config; record it with mode `none`.
    case remember(key: String, name: String)
    /// Make `external` a mirror of `builtin`: the panel stays the main display and keeps every
    /// window, the external shows its picture. Never the other way round.
    case mirror(external: UInt32, builtin: UInt32)
    case dim(builtin: UInt32)
    case restore(builtin: UInt32)
}

/// Restoring never goes below this, so a bad saved value cannot restore to black.
public let restoreFloor: Float = 0.3

public func restoreValue(saved: Float?) -> Float {
    max(saved ?? 0, restoreFloor)
}

/// True when the built-in panel is online and an online external display mirrors it. That is the
/// only arrangement in which the panel may be dark, because the external is showing its picture.
/// The reverse arrangement (the panel mirroring the external, as v0 set it up) does not count.
public func builtinIsMirrored(_ displays: [Display]) -> Bool {
    guard let builtin = displays.first(where: \.isBuiltin) else { return false }
    return displays.contains { !$0.isBuiltin && $0.mirrorsDisplayID == builtin.id }
}

/// Pure decision: what to do given the online displays, the config and whether we dimmed the panel.
/// Order: `remember` entries first, then `mirror`, then `dim` or `restore`.
public func plan(displays: [Display], config: Config, dimmed: Bool) -> [Action] {
    let externals = displays.filter { !$0.isBuiltin }
    var actions: [Action] = externals
        .filter { config.displays[$0.key] == nil }
        .map { .remember(key: $0.key, name: $0.name) }

    guard let builtin = displays.first(where: \.isBuiltin) else { return actions }

    if let external = externals.first(where: { config.displays[$0.key]?.mode == .mirror }) {
        if external.mirrorsDisplayID != builtin.id {
            actions.append(.mirror(external: external.id, builtin: builtin.id))
        }
        if !dimmed {
            actions.append(.dim(builtin: builtin.id))
        }
    } else if dimmed {
        actions.append(.restore(builtin: builtin.id))
    }
    return actions
}

/// Maintenance pass, run after every evaluation and on each watchdog tick, only while we have dimmed
/// the panel: restore when no online external mirrors the panel any more (unplugged, or re-arranged in
/// System Settings), re-dim when the system or the user turned the backlight back up while mirrored.
public func maintain(displays: [Display], brightness: Float?) -> Action? {
    guard let builtin = displays.first(where: \.isBuiltin) else { return nil }
    if !builtinIsMirrored(displays) { return .restore(builtin: builtin.id) }
    if let brightness, brightness > 0.01 { return .dim(builtin: builtin.id) }
    return nil
}
