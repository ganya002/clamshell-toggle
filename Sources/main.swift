import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "Current state: unknown", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Toggle", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusLine.isEnabled = false
        toggleItem.target = self
        toggleItem.action = #selector(toggle(_:))

        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Clamshell Toggle",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
        refreshAll()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshAll() }

    private var sleepDisabledNow: Bool { AppDelegate.sleepDisabled() }

    static func sleepDisabled() -> Bool {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.range(of: "SleepDisabled[[:space:]]+1", options: .regularExpression) != nil
    }

    @objc private func toggle(_ sender: Any?) {
        let enable = !sleepDisabledNow
        let p = Process()
        let errPipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "/usr/bin/pmset", "disablesleep", enable ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do { try p.run() } catch {
            showSetupAlert(detail: error.localizedDescription)
            return
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let detail = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            showSetupAlert(detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }
        refreshAll()
    }

    private func refreshAll() {
        let on = sleepDisabledNow
        statusLine.title = on ? "State: sleep disabled (clamshell ready)" : "State: normal sleep"
        toggleItem.title = on ? "Turn Off (restore normal sleep)" : "Turn On (allow lid closed on battery)"
        statusItem.button?.title = on ? "Clamshell ON" : "Clamshell OFF"
    }

    private func showSetupAlert(detail: String) {
        let cmd = "echo '\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep *' | sudo tee /etc/sudoers.d/clamshell >/dev/null && sudo chmod 0440 /etc/sudoers.d/clamshell"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "One-time setup needed"
        alert.informativeText = """
            The passwordless pmset permission is missing.
            Run this once in Terminal:

            \(cmd)

            Error: \(detail)
            """
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
