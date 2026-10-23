import AppKit
import MirrorCore

/// Owns the event sources (display reconfiguration, wake, watchdog) and executes the planner's actions.
final class Controller {
    let configURL: URL
    private let defaults = UserDefaults.standard
    private var debounce: Timer?
    private var watchdog: Timer?

    init(configURL: URL = Config.defaultURL) {
        self.configURL = configURL
    }

    /// Non-nil while we have dimmed the panel; the value is the brightness to restore.
    /// Persisted so a relaunch after a crash or kill still knows to restore.
    var savedBrightness: Float? {
        get { defaults.object(forKey: "savedBrightness") as? Float }
        set {
            if let newValue { defaults.set(newValue, forKey: "savedBrightness") }
            else { defaults.removeObject(forKey: "savedBrightness") }
        }
    }

    func start() {
        CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleEvaluate() }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.watchdogTick() }
        if !Brightness.available { log("DisplayServices brightness unavailable; the built-in panel will never be dimmed") }
        evaluate()
    }

    func shutdown() {
        restoreNow()
        CGDisplayRemoveReconfigurationCallback(reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Display changes arrive in bursts; coalesce them into one evaluation.
    func scheduleEvaluate() {
        DispatchQueue.main.async {
            self.debounce?.invalidate()
            self.debounce = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.evaluate() }
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
                return  // a failed mirror must not be followed by a dim
            }
        }
    }

    @discardableResult
    private func execute(_ action: Action) -> Bool {
        switch action {
        case .remember:
            return true
        case .mirror(let builtin, let master):
            return Displays.mirror(builtin: builtin, master: master)
        case .dim(let builtin):
            guard let current = Brightness.get(builtin) else {
                log("cannot read built-in brightness; not dimming")
                return false
            }
            if savedBrightness == nil { savedBrightness = current }  // a re-dim keeps the original value
            if Brightness.set(builtin, 0) { return true }
            savedBrightness = nil
            return false
        case .restore(let builtin):
            guard savedBrightness != nil else { return true }
            guard Brightness.set(builtin, restoreValue(saved: savedBrightness)) else { return false }
            savedBrightness = nil
            return true
        }
    }

    func setMode(_ mode: Mode, for display: Display) {
        var config = currentConfig()
        config.displays[display.key] = DisplayEntry(name: display.name, mode: mode)
        save(config)
        if mode == .none, let builtin = Displays.snapshot().first(where: \.isBuiltin),
           builtin.mirrorsDisplayID == display.id {
            _ = Displays.unmirror(builtin: builtin.id)
        }
        evaluate()
    }

    /// Lights the panel and stops managing it until the next display event re-evaluates.
    func restoreNow() {
        if let builtin = Displays.snapshot().first(where: \.isBuiltin) { execute(.restore(builtin: builtin.id)) }
    }

    /// Only active while we have dimmed the panel; see `maintain` for the two cases it covers.
    private func watchdogTick() {
        guard savedBrightness != nil else { return }
        let displays = Displays.snapshot()
        let brightness = displays.first(where: \.isBuiltin).flatMap { Brightness.get($0.id) }
        if let action = maintain(displays: displays, brightness: brightness) {
            log("watchdog: \(action)")
            execute(action)
        }
    }

    private func save(_ config: Config) {
        do { try config.save(to: configURL) } catch { log("cannot save config: \(error)") }
    }
}

private let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
    guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
    Unmanaged<Controller>.fromOpaque(userInfo).takeUnretainedValue().scheduleEvaluate()
}
