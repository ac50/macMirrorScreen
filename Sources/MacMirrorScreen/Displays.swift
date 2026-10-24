import AppKit
import CoreGraphics
import MirrorCore
import os

private let logger = Logger(subsystem: "io.github.ac50.MacMirrorScreen", category: "app")

/// Unified log for Console.app (when launched from Finder) and stderr (when run from a terminal).
func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")
    FileHandle.standardError.write(Data("[MacMirrorScreen] \(message)\n".utf8))
}

private let nullDisplay: CGDirectDisplayID = 0

/// CoreGraphics display enumeration and mirroring.
enum Displays {
    static func snapshot() -> [Display] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            Display(
                id: id,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                key: Config.key(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                serial: CGDisplaySerialNumber(id)),
                name: name(of: id),
                mirrorsDisplayID: CGDisplayMirrorsDisplay(id))
        }
    }

    /// Makes `display` a mirror of `master`: the external a mirror of the built-in panel, so the panel
    /// stays the main display. True only when CoreGraphics confirms the new arrangement.
    /// A master that is itself a mirror (how v0 left the panel) is released first, in its own
    /// transaction, so the new mirror set has one unambiguous primary.
    static func mirror(_ display: CGDirectDisplayID, of master: CGDirectDisplayID) -> Bool {
        if CGDisplayMirrorsDisplay(master) != nullDisplay {
            log("display \(master) is itself a mirror; releasing it so that it can be the mirror source")
            guard configure(master, mirrorOf: nullDisplay) else { return false }
        }
        return configure(display, mirrorOf: master) && CGDisplayMirrorsDisplay(display) == master
    }

    static func unmirror(_ display: CGDirectDisplayID) -> Bool {
        configure(display, mirrorOf: nullDisplay)
    }

    private static func configure(_ display: CGDirectDisplayID, mirrorOf master: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let error = CGConfigureDisplayMirrorOfDisplay(config, display, master)
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            log("mirror configuration failed: \(error.rawValue)")
            return false
        }
        let done = CGCompleteDisplayConfiguration(config, .permanently)
        if done != .success { log("completing display configuration failed: \(done.rawValue)") }
        return done == .success
    }

    static func name(of id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }
        return screen?.localizedName ?? "Display \(id)"
    }
}

/// Built-in panel backlight via the private DisplayServices framework, resolved at run time
/// so the binary has no link-time dependency on it. Unavailable symbols simply disable dimming.
enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn: GetFn? = symbol("DisplayServicesGetBrightness")
    private static let setFn: SetFn? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var available: Bool { getFn != nil && setFn != nil }

    static func get(_ id: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getFn, getFn(id, &value) == 0 else { return nil }
        return value
    }

    static func set(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let setFn else { return false }
        let status = setFn(id, value)
        if status != 0 { log("setting brightness \(value) failed: \(status)") }
        return status == 0
    }
}
