import AppKit
import MirrorCore

/// Owns the event sources (display reconfiguration, wake, watchdog) and executes the planner's actions.
final class Controller {
    let configURL: URL
    private var debounce: Timer?
    private var watchdog: Timer?

    init(configURL: URL = Config.defaultURL) {
        self.configURL = configURL
    }

    private var stateURL: URL { DimState.url(besideConfig: configURL) }

    /// Non-nil while we have dimmed the panel; the value is the brightness to restore.
    /// Persisted beside the config so a relaunch after a crash or kill still knows to restore.
    var savedBrightness: Float? { DimState.load(from: stateURL) }

    private func setSavedBrightness(_ value: Float?) -> Bool {
        do {
            try DimState.save(value, to: stateURL)
            return true
        } catch {
            log("cannot write dim marker: \(error)")
            return false
        }
    }

    func start() {
        CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleEvaluate() }
        }
        watchdog = timer(10, repeats: true) { [weak self] in self?.maintainPass() }
        if !Brightness.available { log("DisplayServices brightness unavailable; the built-in panel will never be dimmed") }

        // Launch net: a dark panel that no external mirrors is never wanted, whoever dimmed it (covers a lost marker).
        let displays = Displays.snapshot()
        if let builtin = displays.first(where: \.isBuiltin), !builtinIsMirrored(displays),
           (Brightness.get(builtin.id) ?? 1) < 0.01 {
            log("launch: built-in panel is dark and not mirrored; restoring")
            restoreNow()
        }
        evaluate()
    }

    func shutdown() {
        if savedBrightness != nil { restoreNow() }
        CGDisplayRemoveReconfigurationCallback(reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Display changes arrive in bursts; coalesce them into one evaluation.
    func scheduleEvaluate() {
        DispatchQueue.main.async {
            self.debounce?.invalidate()
            self.debounce = self.timer(1, repeats: false) { [weak self] in self?.evaluate() }
        }
    }

    func currentConfig() -> Config {
        (try? Config.load(from: configURL)) ?? Config()
    }

    func evaluate() {
        var config = Config()
        var writable = true
        do {
            config = try Config.load(from: configURL)
        } catch {
            log("config unreadable, treating as empty and leaving the file alone: \(error)")
            writable = false
        }
        var updated = config
        defer { if writable, updated != config { save(updated) } }

        for action in plan(displays: Displays.snapshot(), config: config, dimmed: savedBrightness != nil) {
            if case .remember(let key, let name) = action {
                updated.displays[key] = DisplayEntry(name: name, mode: .none)
            } else if !execute(action) {
                break  // a failed mirror must not be followed by a dim
            }
        }
        // Also after a failure: a dark panel that no external mirrors (say a re-arrangement that stopped
        // half-way) is relit now, not at the next watchdog tick. Waking the displays often brings the
        // panel back at a faint brightness; that is re-dimmed here too.
        maintainPass()
    }

    @discardableResult
    private func execute(_ action: Action) -> Bool {
        switch action {
        case .remember:
            return true
        case .mirror(let external, let builtin):
            return Displays.mirror(external, of: builtin)
        case .dim(let builtin):
            guard let current = Brightness.get(builtin) else {
                log("cannot read built-in brightness; not dimming")
                return false
            }
            // The marker must be durable before the panel goes dark; a re-dim keeps the original value,
            // also when it fails, so the saved brightness and every restore net survive.
            let firstDim = savedBrightness == nil
            guard !firstDim || setSavedBrightness(current) else { return false }
            if Brightness.set(builtin, 0) { return true }
            if firstDim { _ = setSavedBrightness(nil) }
            return false
        case .restore(let builtin):
            guard savedBrightness != nil else { return true }
            guard Brightness.set(builtin, restoreValue(saved: savedBrightness)) else { return false }
            return setSavedBrightness(nil)
        }
    }

    func setMode(_ mode: Mode, for display: Display) {
        // Like evaluate(), never overwrite a config file that does not parse.
        guard var config = try? Config.load(from: configURL) else {
            log("config unreadable; mode not changed, fix the file first")
            return
        }
        // An external that mirrors the panel has no screen of its own, so its live name is only the
        // fallback; keep the name on file then.
        var name = display.name
        if name == Displays.fallbackName(display.id), let known = config.displays[display.key]?.name { name = known }
        config.displays[display.key] = DisplayEntry(name: name, mode: mode)
        save(config)
        if mode == .none {
            let displays = Displays.snapshot()
            if let builtin = displays.first(where: \.isBuiltin),
               let external = displays.first(where: { $0.id == display.id }) {
                // Release whichever side is the mirror, including the reverse arrangement v0 left behind.
                if external.mirrorsDisplayID == builtin.id {
                    _ = Displays.unmirror(external.id)
                } else if builtin.mirrorsDisplayID == external.id {
                    _ = Displays.unmirror(builtin.id)
                }
            }
        }
        evaluate()
    }

    /// Explicit escape (menu, launch, quit): lights the panel if it is dark, whoever dimmed it,
    /// and stops managing it until the next display event re-evaluates. The marker goes only once the
    /// panel is lit: while it stays dark and nothing mirrors it, the marker keeps the watchdog retrying.
    func restoreNow() {
        let displays = Displays.snapshot()
        guard let builtin = displays.first(where: \.isBuiltin) else {
            log("restore requested but the built-in display is offline (lid closed?); keeping the marker")
            return
        }
        let target = restoreValue(saved: savedBrightness)
        if (Brightness.get(builtin.id) ?? 0) >= target || Brightness.set(builtin.id, target) {
            _ = setSavedBrightness(nil)
        } else {
            log("relighting the built-in panel failed; the watchdog retries while nothing mirrors it")
            if savedBrightness == nil, !builtinIsMirrored(displays) { _ = setSavedBrightness(target) }
        }
    }

    /// Runs after every evaluation and on each watchdog tick, only while we have dimmed the panel;
    /// see `maintain` for the two cases it covers.
    private func maintainPass() {
        guard savedBrightness != nil else { return }
        let displays = Displays.snapshot()
        let brightness = displays.first(where: \.isBuiltin).flatMap { Brightness.get($0.id) }
        if let action = maintain(displays: displays, brightness: brightness) {
            log("maintain: \(action)")
            execute(action)
        }
    }

    /// Timers in the common run-loop mode keep firing while the status-bar menu is open.
    /// The tolerance lets the kernel coalesce our wakeups with other timers (Apple's energy guidance).
    private func timer(_ interval: TimeInterval, repeats: Bool, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in block() }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func save(_ config: Config) {
        do { try config.save(to: configURL) } catch { log("cannot save config: \(error)") }
    }
}

private let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
    guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
    Unmanaged<Controller>.fromOpaque(userInfo).takeUnretainedValue().scheduleEvaluate()
}
