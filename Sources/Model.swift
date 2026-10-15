import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var prefs: Preferences
    @Published var runtime: RuntimeState
    @Published var agents: [String] = []
    @Published var now = Date()
    @Published var picture = AwakePicture(timerEndsAt: nil, scheduleEndMinute: nil, agents: [], manual: false)
    @Published var status = "Asleep"

    let gate = PowerGate()
    private let defaults = UserDefaults.standard
    private var lastRequested: Bool?
    private var applyFailed = false
    private var alertVisible = false
    private var clock: Timer?
    private var scanSlot = 0
    private var scanning = false

    var onStatusChange: (() -> Void)?
    var onTick: (() -> Void)?

    init() {
        prefs = Preferences.load(from: UserDefaults.standard.data(forKey: Key.prefs))
        runtime = RuntimeState.load(from: UserDefaults.standard.data(forKey: Key.runtime))
        if defaults.object(forKey: Key.runtime) == nil {
            runtime.manualOn = Power.sleepDisabled()
        }
        recompute(apply: true)
    }

    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        tick()
    }

    func toggleFromMenu() {
        applyFailed = false
        if picture.awake {
            runtime.manualOn = false
            runtime.timerEndsAt = nil
            runtime.timerMinutes = nil
            if prefs.scheduleEnabled && Engine.isScheduled(prefs, now, .current) {
                runtime.pausedSchedule = true
            }
            if prefs.followAgents && !agents.isEmpty {
                runtime.pausedAgents = true
            }
        } else {
            runtime.manualOn = true
            runtime.pausedAgents = false
            runtime.pausedSchedule = false
        }
        persistRuntime()
        recompute(apply: true)
    }

    func startTimer(minutes: Int) {
        applyFailed = false
        let minutes = DurationText.clamp(minutes)
        prefs.dialMinutes = minutes
        runtime.timerEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        runtime.timerMinutes = minutes
        runtime.pausedAgents = false
        runtime.pausedSchedule = false
        persistPrefs()
        persistRuntime()
        recompute(apply: true)
    }

    func stopTimer() {
        runtime.timerEndsAt = nil
        runtime.timerMinutes = nil
        persistRuntime()
        recompute(apply: true)
    }

    func setDial(_ minutes: Int) {
        prefs.dialMinutes = DurationText.clamp(minutes)
        persistPrefs()
    }

    func setFollowAgents(_ enabled: Bool) {
        prefs.followAgents = enabled
        if enabled { runtime.pausedAgents = false }
        persistPrefs()
        persistRuntime()
        recompute(apply: true)
    }

    func setScheduleEnabled(_ enabled: Bool) {
        prefs.scheduleEnabled = enabled
        if enabled { runtime.pausedSchedule = false }
        persistPrefs()
        persistRuntime()
        recompute(apply: true)
    }

    func toggleDay(_ weekday: Int) {
        if prefs.days.contains(weekday) {
            prefs.days.removeAll { $0 == weekday }
        } else {
            prefs.days.append(weekday)
            prefs.days.sort()
        }
        prefs = prefs.sanitized()
        persistPrefs()
        recompute(apply: true)
    }

    func setStart(_ date: Date) {
        prefs.startMinute = Engine.minute(of: date, calendar: .current)
        prefs = prefs.sanitized()
        persistPrefs()
        recompute(apply: true)
    }

    func setEnd(_ date: Date) {
        prefs.endMinute = Engine.minute(of: date, calendar: .current)
        prefs = prefs.sanitized()
        persistPrefs()
        recompute(apply: true)
    }

    func setExtraAgents(_ text: String) {
        prefs.extraAgents = text.split(separator: ",").map { String($0) }
        prefs = prefs.sanitized()
        persistPrefs()
        scanSlot = 2
        tick()
    }

    private func tick() {
        now = Date()
        scanSlot += 1
        if scanSlot >= 3 {
            scanSlot = 0
            scanAgents()
        }
        recompute(apply: !applyFailed)
    }

    private func scanAgents() {
        guard !scanning else { return }
        scanning = true
        let extra = prefs.extraAgents
        Task.detached { [weak self] in
            let found = AgentScan.current(extra: extra)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanning = false
                if found != self.agents {
                    self.agents = found
                    self.recompute(apply: !self.applyFailed)
                }
            }
        }
    }

    private func recompute(apply: Bool) {
        let runtimeBefore = runtime
        let statusBefore = status
        let pictureBefore = picture
        let agentsBefore = agents
        Engine.normalize(now: now, calendar: .current, prefs: prefs, runtime: &runtime, agents: agents)
        picture = Engine.picture(now: now, calendar: .current, prefs: prefs, runtime: runtime, agents: agents)
        status = Engine.sentence(picture: picture, now: now, calendar: .current)
        if runtime != runtimeBefore {
            persistRuntime()
        }
        if status != statusBefore || picture != pictureBefore || agents != agentsBefore {
            onStatusChange?()
        } else {
            onTick?()
        }
        guard apply, !CommandLine.arguments.contains("--preview") else { return }
        let want = picture.awake
        guard want != lastRequested else { return }
        lastRequested = want
        Task.detached { [gate] in
            do {
                try gate.sync(to: want)
            } catch {
                await MainActor.run { [weak self] in
                    self?.lastRequested = nil
                    self?.applyFailed = true
                    self?.present(error)
                }
            }
        }
    }

    private func present(_ error: Error) {
        guard !alertVisible else { return }
        alertVisible = true
        let detail = (error as? PowerError)?.description ?? error.localizedDescription
        let command = "echo '\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep *' | sudo tee /etc/sudoers.d/clamshell >/dev/null && sudo chmod 0440 /etc/sudoers.d/clamshell"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "One-time setup needed"
        alert.informativeText = """
        Clamshell Toggle needs a passwordless permission for pmset. Run this once in Terminal:

        \(command)

        \(detail)
        """
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
        alertVisible = false
    }

    private func persistPrefs() {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: Key.prefs)
        }
    }

    private func persistRuntime() {
        if let data = try? JSONEncoder().encode(runtime) {
            defaults.set(data, forKey: Key.runtime)
        }
    }

    private enum Key {
        static let prefs = "clamshell.preferences"
        static let runtime = "clamshell.runtime"
    }
}
