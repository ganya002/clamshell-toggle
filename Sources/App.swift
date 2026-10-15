import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Asleep", action: nil, keyEquivalent: "")
    private let powerLine = NSMenuItem(title: "Power: Checking…", action: nil, keyEquivalent: "")
    private let warningLine = NSMenuItem(title: "Closed lid on battery drains faster", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Turn on", action: nil, keyEquivalent: "")
    private var settings: SettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusLine.isEnabled = false
        powerLine.isEnabled = false
        warningLine.isEnabled = false
        warningLine.isHidden = true
        toggleItem.target = self
        toggleItem.action = #selector(toggle(_:))

        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(statusLine)
        menu.addItem(powerLine)
        menu.addItem(warningLine)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clamshell Toggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.toolTip = "Quitting leaves the lid the way it is"
        menu.addItem(quit)
        statusItem.menu = menu

        model.onStatusChange = { [weak self] in
            self?.refreshMenu()
            self?.settings?.sync()
        }
        model.onTick = { [weak self] in
            self?.settings?.updateCountdown()
        }
        model.start()
        refreshMenu()

        if CommandLine.arguments.contains("--settings") {
            showSettings(nil)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    @objc private func toggle(_ sender: Any?) {
        model.toggleFromMenu()
        refreshMenu()
    }

    @objc private func showSettings(_ sender: Any?) {
        if settings == nil {
            settings = SettingsController(model: model)
        }
        settings?.show()
    }

    private func refreshMenu() {
        let awake = model.picture.awake
        let battery = Power.battery()
        statusLine.title = model.status
        if let percentage = battery.percentage {
            powerLine.title = "\(battery.source), \(percentage)%"
        } else {
            powerLine.title = battery.source
        }
        warningLine.isHidden = !(awake && battery.onBattery)
        toggleItem.title = awake ? "Turn off" : "Turn on"
        statusItem.button?.image = Glyph.image(awake: awake)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = model.status
        statusItem.button?.appearsDisabled = false
    }
}

@MainActor
final class SettingsController: NSWindowController {
    private var host: SettingsView?

    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 448, height: 508),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clamshell"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.sharingType = .readOnly
        super.init(window: panel)

        let effect = NSGlassEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.autoresizingMask = [.width, .height]
        effect.style = .regular
        effect.cornerRadius = 18
        let host = SettingsView(model: model)
        host.autoresizingMask = [.width, .height]
        host.frame = effect.bounds
        effect.contentView = host
        panel.contentView = effect
        self.host = host
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.sharingType = .readOnly
        host?.sync()
        host?.reveal()
    }

    func sync() {
        host?.sync()
    }

    func updateCountdown() {
        host?.updateCountdown()
    }
}

@main
@MainActor
enum ClamshellMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
