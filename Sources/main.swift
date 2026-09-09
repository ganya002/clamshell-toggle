import AppKit

private struct CommandResult {
    let status: Int32
    let output: String
    let error: String
}

private struct PowerInfo {
    let source: String
    let percentage: Int?
    let isBattery: Bool
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private let statusLine = NSMenuItem(title: "Clamshell Mode: Checking…", action: nil, keyEquivalent: "")
    private let powerLine = NSMenuItem(title: "Power: Checking…", action: nil, keyEquivalent: "")
    private let warningLine = NSMenuItem(title: "Lid-closed use on battery can drain power quickly", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Enable Clamshell Mode", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh Status", action: nil, keyEquivalent: "r")
    private let aboutItem = NSMenuItem(title: "About Clamshell Toggle", action: nil, keyEquivalent: "")

    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureStatusItem()
        configureMenu()

        refreshAll()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshAll()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "Clamshell Toggle"
        button.setAccessibilityLabel("Clamshell Toggle")
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        statusLine.isEnabled = false
        statusLine.image = symbol("laptopcomputer")
        menu.addItem(statusLine)

        powerLine.isEnabled = false
        menu.addItem(powerLine)

        warningLine.isEnabled = false
        warningLine.image = symbol("exclamationmark.triangle.fill")
        warningLine.isHidden = true
        menu.addItem(warningLine)

        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggle(_:))
        toggleItem.image = symbol("power")
        menu.addItem(toggleItem)

        refreshItem.target = self
        refreshItem.action = #selector(refresh(_:))
        refreshItem.image = symbol("arrow.clockwise")
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        aboutItem.target = self
        aboutItem.action = #selector(showAbout(_:))
        aboutItem.image = symbol("info.circle")
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit Clamshell Toggle (keeps current state)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = symbol("xmark.circle")
        menu.addItem(quitItem)
    }

    @objc private func toggle(_ sender: Any?) {
        guard let currentState = Self.sleepDisabled() else {
            showErrorAlert(
                title: "Couldn’t read clamshell state",
                detail: "pmset did not return a readable SleepDisabled value. Try Refresh Status or run `pmset -g` in Terminal."
            )
            return
        }

        let enable = !currentState
        let result = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", enable ? "1" : "0"])

        guard result.status == 0 else {
            showSetupAlert(detail: result.error.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }

        refreshAll()
    }

    @objc private func refresh(_ sender: Any?) {
        refreshAll()
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Clamshell Toggle \(version)"
        alert.informativeText = "Keeps your Mac awake with the lid closed, including while on battery, by toggling macOS pmset disablesleep.\n\nThe menu bar icon updates with the current state and the menu shows your power source and battery percentage."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func refreshAll() {
        let state = Self.sleepDisabled()
        let power = Self.powerInfo()

        switch state {
        case .some(true):
            statusLine.title = "Clamshell Mode: ON — sleep disabled"
            toggleItem.title = "Disable Clamshell Mode"
            toggleItem.state = .on
            toggleItem.isEnabled = true
            setStatusIcon(symbolName: "laptopcomputer", tooltip: "Clamshell Mode: ON")
        case .some(false):
            statusLine.title = "Clamshell Mode: OFF — normal sleep"
            toggleItem.title = "Enable Clamshell Mode"
            toggleItem.state = .off
            toggleItem.isEnabled = true
            setStatusIcon(symbolName: "moon.zzz", tooltip: "Clamshell Mode: OFF — normal sleep")
        case .none:
            statusLine.title = "Clamshell Mode: Unknown"
            toggleItem.title = "Unable to read current state"
            toggleItem.state = .off
            toggleItem.isEnabled = false
            setStatusIcon(symbolName: "questionmark.circle", tooltip: "Clamshell Mode: Unknown")
        }

        if let percentage = power.percentage {
            powerLine.title = "Power: \(power.source) · \(percentage)%"
        } else {
            powerLine.title = "Power: \(power.source)"
        }
        powerLine.image = symbol(power.isBattery ? "battery.100" : "bolt.fill")

        warningLine.isHidden = !(state == true && power.isBattery)
    }

    private func setStatusIcon(symbolName: String, tooltip: String) {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = symbol(symbolName, pointSize: 14)
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    private func symbol(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = true
        return image
    }

    private static func sleepDisabled() -> Bool? {
        let result = run("/usr/bin/pmset", ["-g"])
        guard result.status == 0 else { return nil }

        if result.output.range(of: "SleepDisabled[[:space:]]+1", options: .regularExpression) != nil {
            return true
        }
        if result.output.range(of: "SleepDisabled[[:space:]]+0", options: .regularExpression) != nil {
            return false
        }
        return nil
    }

    private static func powerInfo() -> PowerInfo {
        let result = run("/usr/bin/pmset", ["-g", "batt"])
        guard result.status == 0 else {
            return PowerInfo(source: "Unknown", percentage: nil, isBattery: false)
        }

        let text = result.output
        let isBattery = text.contains("Battery Power")
        let source: String
        if isBattery {
            source = "Battery"
        } else if text.contains("AC Power") {
            source = "Power Adapter"
        } else {
            source = "Unknown"
        }

        var percentage: Int?
        if let match = text.range(of: #"[0-9]{1,3}%"#, options: .regularExpression) {
            percentage = Int(text[match].dropLast())
        }

        return PowerInfo(source: source, percentage: percentage, isBattery: isBattery)
    }

    private static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "", error: error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            status: process.terminationStatus,
            output: String(data: outputData, encoding: .utf8) ?? "",
            error: String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    private func showSetupAlert(detail: String) {
        let command = "printf '%s\\n' \"$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1\" | sudo tee /etc/sudoers.d/clamshell >/dev/null && sudo chmod 0440 /etc/sudoers.d/clamshell && sudo visudo -cf /etc/sudoers.d/clamshell"

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "One-time setup needed"
        alert.informativeText = """
        Clamshell Toggle needs narrowly scoped permission to switch sleep on and off without asking for your password every time.

        Run this once in Terminal:

        \(command)

        \(detail.isEmpty ? "" : "Error: \(detail)")
        """
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    private func showErrorAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
