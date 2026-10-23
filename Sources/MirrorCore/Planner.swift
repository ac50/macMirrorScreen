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
    case mirror(builtin: UInt32, master: UInt32)
    case dim(builtin: UInt32)
    case restore(builtin: UInt32)
}

/// Restoring never goes below this, so a bad saved value cannot restore to black.
public let restoreFloor: Float = 0.3

public func restoreValue(saved: Float?) -> Float {
    max(saved ?? 0, restoreFloor)
}

/// Pure decision: what to do given the online displays, the config and whether we dimmed the panel.
/// Order: `remember` entries first, then `mirror`, then `dim` or `restore`.
public func plan(displays: [Display], config: Config, dimmed: Bool) -> [Action] {
    let externals = displays.filter { !$0.isBuiltin }
    var actions: [Action] = externals
        .filter { config.displays[$0.key] == nil }
        .map { .remember(key: $0.key, name: $0.name) }

    guard let builtin = displays.first(where: \.isBuiltin) else { return actions }

    if let master = externals.first(where: { config.displays[$0.key]?.mode == .mirror }) {
        if builtin.mirrorsDisplayID != master.id {
            actions.append(.mirror(builtin: builtin.id, master: master.id))
        }
        if !dimmed {
            actions.append(.dim(builtin: builtin.id))
        }
    } else if dimmed {
        actions.append(.restore(builtin: builtin.id))
    }
    return actions
}

/// Maintenance pass, run periodically only while we have dimmed the panel:
/// restore when the panel no longer mirrors an online external (the dark-panel-with-windows case),
/// re-dim when the system or the user turned the backlight back up while still mirrored.
public func maintain(displays: [Display], brightness: Float?) -> Action? {
    guard let builtin = displays.first(where: \.isBuiltin) else { return nil }
    let mirrored = displays.contains { !$0.isBuiltin && $0.id == builtin.mirrorsDisplayID }
    if !mirrored { return .restore(builtin: builtin.id) }
    if let brightness, brightness > 0.01 { return .dim(builtin: builtin.id) }
    return nil
}
