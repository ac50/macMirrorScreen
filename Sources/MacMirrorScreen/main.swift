import AppKit
import MirrorCore
import ServiceManagement

private struct ModeChoice {
    let display: Display
    let mode: Mode
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = Controller()
    private var statusItem: NSStatusItem!
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "MacMirrorScreen")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        for sig in [SIGTERM, SIGINT, SIGHUP] { trap(sig) }
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = controller.currentConfig()
        let externals = Displays.snapshot().filter { !$0.isBuiltin }
        if externals.isEmpty { menu.addItem(headerItem("No external display")) }
        for display in externals {
            let entry = config.displays[display.key]
            // The name on file: while the external mirrors the panel it has no screen, hence no live name.
            menu.addItem(headerItem("External: \(entry?.name ?? display.name)"))
            let current = entry?.mode ?? Mode.none
            for mode in Mode.allCases {
                let choice = actionItem(mode == .mirror ? "Mirror built-in and turn it off" : "Do nothing", #selector(chooseMode(_:)))
                choice.representedObject = ModeChoice(display: display, mode: mode)
                choice.state = mode == current ? .on : .off
                choice.indentationLevel = 1
                menu.addItem(choice)
            }
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Restore built-in display now", #selector(restoreNow)))
        menu.addItem(actionItem("Open config file", #selector(openConfig)))
        let login = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacMirrorScreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func headerItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModeChoice else { return }
        controller.setMode(choice.mode, for: choice.display)
    }

    @objc private func restoreNow() {
        controller.restoreNow()
    }

    @objc private func openConfig() {
        let url = controller.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try Config().save(to: url) } catch { log("cannot create config: \(error)") }
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            log("launch at login: \(error)")
        }
    }

    // MARK: Signals

    /// SIGTERM/SIGINT/SIGHUP go through the normal termination path so the panel is restored.
    private func trap(_ sig: Int32) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        signalSources.append(source)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
