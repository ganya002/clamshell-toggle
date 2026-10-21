import AppKit

private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

private func label(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let updater = Updater()
    private let timerChoices = [15, 30, 60, 120, 240, 480]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        // An update relaunch hides the old icon, and macOS remembers that. Always start visible.
        statusItem.isVisible = true

        model.onStatusChange = { [weak self] in self?.refreshIcon() }
        model.onTick = { [weak self] in self?.refreshStatusLine() }
        model.start()
        refreshIcon()

        if Updater.supported {
            updater.canRelaunch = { NSApp.modalWindow == nil }
            updater.willRelaunch = { [weak self] in self?.statusItem.isVisible = false }
            updater.didFailRelaunch = { [weak self] in self?.statusItem.isVisible = true }
            updater.start()
        }
    }

    // The menu is built fresh each time it opens, so it always shows the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ActionItem(model.picture.awake ? "Turn Off" : "Turn On") { [model] in model.toggleFromMenu() })
        if let end = model.picture.timerEndsAt {
            let left = DurationText.countdown(end.timeIntervalSince(model.now))
            menu.addItem(ActionItem("Stop Timer (\(left) left)") { [model] in model.stopTimer() })
        } else {
            menu.addItem(timerMenu())
        }
        menu.addItem(.separator())
        menu.addItem(scheduleMenu())
        menu.addItem(agentsMenu())

        if Updater.supported {
            menu.addItem(.separator())
            addUpdateItems()
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clamshell Toggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.toolTip = "Quitting leaves the lid the way it is"
        menu.addItem(quit)
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        items.forEach(child.addItem)
        parent.submenu = child
        return parent
    }

    private func timerMenu() -> NSMenuItem {
        var items = timerChoices.map { minutes in
            ActionItem(DurationText.words(minutes)) { [model] in model.startTimer(minutes: minutes) }
        } as [NSMenuItem]
        items.append(.separator())
        items.append(ActionItem("Custom…") { [weak self] in self?.askDuration() })
        return submenu("Keep Awake For", items)
    }

    private func scheduleMenu() -> NSMenuItem {
        let prefs = model.prefs
        var items: [NSMenuItem] = [
            ActionItem("Keep Awake on a Schedule", checked: prefs.scheduleEnabled) { [model] in
                model.setScheduleEnabled(!model.prefs.scheduleEnabled)
            },
            label(scheduleSummary()),
            .separator(),
        ]
        let calendar = Calendar.current
        for offset in 0..<7 {
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            items.append(ActionItem(calendar.weekdaySymbols[weekday - 1], checked: prefs.days.contains(weekday)) { [model] in
                model.toggleDay(weekday)
            })
        }
        items.append(.separator())
        items.append(ActionItem("Set Hours…") { [weak self] in self?.askHours() })
        return submenu("Schedule", items)
    }

    private func scheduleSummary() -> String {
        let prefs = model.prefs
        if prefs.days.isEmpty { return "No days selected" }
        let calendar = Calendar.current
        let set = Set(prefs.days)
        let days: String
        if set == [2, 3, 4, 5, 6] {
            days = "Weekdays"
        } else if set == [1, 7] {
            days = "Weekends"
        } else if set.count == 7 {
            days = "Every day"
        } else {
            days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
                .filter(set.contains)
                .map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        }
        return "\(days), \(Engine.clock(prefs.startMinute, calendar: calendar)) to \(Engine.clock(prefs.endMinute, calendar: calendar))"
    }

    private func agentsMenu() -> NSMenuItem {
        var items: [NSMenuItem] = [
            ActionItem("Stay Awake While Agents Run", checked: model.prefs.followAgents) { [model] in
                model.setFollowAgents(!model.prefs.followAgents)
            },
        ]
        if !model.agents.isEmpty {
            items.append(label("Running: " + model.agents.joined(separator: ", ")))
        }
        items.append(.separator())
        let extra = model.prefs.extraAgents
        items.append(ActionItem(extra.isEmpty ? "Add Other Programs…" : "Other Programs: \(extra.joined(separator: ", "))…") { [weak self] in
            self?.askPrograms()
        })
        return submenu("Agents", items)
    }

    private func addUpdateItems() {
        let title: String
        var enabled = true
        switch updater.state {
        case .idle: title = "Check for Updates…"
        case .checking: title = "Checking for Updates…"; enabled = false
        case .available(let info): title = "Update to \(info.version)…"
        case .installing(let info): title = "Updating to \(info.version)…"; enabled = false
        case .ready: title = "Restart to Finish Update"
        case .failed: title = "Update Failed. Try Again…"
        }
        menu.addItem(ActionItem(title, enabled: enabled) { [weak self] in
            Task { await self?.updateFromMenu() }
        })
        menu.addItem(ActionItem("Update Automatically", checked: updater.automatic) { [updater] in
            updater.automatic.toggle()
        })
    }

    private func refreshStatusLine() {
        if let end = model.picture.timerEndsAt,
           let item = menu.items.first(where: { $0.title.hasPrefix("Stop Timer") }) {
            item.title = "Stop Timer (\(DurationText.countdown(end.timeIntervalSince(model.now))) left)"
        }
    }

    private func refreshIcon() {
        let awake = model.picture.awake
        statusItem.button?.image = Glyph.image(awake: awake)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = model.status
    }

    // MARK: Dialogs

    private func dialog(_ title: String, _ detail: String, accessory: NSView?, button: String = "Set") -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.accessoryView = accessory
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func textField(_ value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = value
        field.placeholderString = placeholder
        return field
    }

    private func askDuration() {
        let field = textField(DurationText.compact(model.prefs.dialMinutes), placeholder: "1h 30m")
        while dialog("Keep awake for how long?", "From 5 minutes to 8 hours. For example 45m, 1h 30m, or 2:15.", accessory: field, button: "Start") {
            if let minutes = DurationText.parse(field.stringValue) {
                model.startTimer(minutes: minutes)
                return
            }
            notify("That is not a duration", "Try something like 45m, 1h 30m, or 2:15.")
        }
    }

    private func askHours() {
        func picker(_ minute: Int) -> NSDatePicker {
            let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.dateValue = Engine.date(minute: minute, calendar: .current)
            return picker
        }
        let start = picker(model.prefs.startMinute)
        let end = picker(model.prefs.endMinute)
        let row = NSStackView(views: [NSTextField(labelWithString: "From"), start, NSTextField(labelWithString: "to"), end])
        row.spacing = 8
        row.frame = NSRect(x: 0, y: 0, width: 280, height: 28)
        guard dialog("Schedule hours", "A block that ends before it starts runs overnight.", accessory: row) else { return }
        model.setStart(start.dateValue)
        model.setEnd(end.dateValue)
    }

    private func askPrograms() {
        let field = textField(model.prefs.extraAgents.joined(separator: ", "), placeholder: "mytool, other")
        guard dialog("Other programs", "Names of programs to treat as agents. Separate them with commas.", accessory: field, button: "Save") else { return }
        model.setExtraAgents(field.stringValue)
    }

    // MARK: Updates

    private func updateFromMenu() async {
        var target: UpdateInfo?
        switch updater.state {
        case .ready:
            updater.relaunch()
            return
        case .checking, .installing:
            return
        case .available(let info):
            target = info
        case .idle, .failed:
            break
        }
        if target == nil {
            switch await updater.check() {
            case .busy:
                return
            case .failed(let message):
                notify("Could not check for updates", message)
                return
            case .upToDate(let version):
                notify("You are up to date", "Clamshell Toggle \(version) is the newest version.")
                return
            case .available(let info):
                guard dialog("Version \(info.version) is available", "Clamshell Toggle builds the new version, then restarts.", accessory: nil, button: "Update") else { return }
                target = info
            }
        }
        guard let info = target else { return }
        if let message = await updater.install(info) {
            notify("The update failed", message)
            return
        }
        updater.relaunch()
    }

    private func notify(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
