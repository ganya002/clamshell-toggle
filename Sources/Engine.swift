import Foundation

struct Preferences: Codable, Equatable, Sendable {
    var followAgents: Bool
    var scheduleEnabled: Bool
    var days: [Int]
    var startMinute: Int
    var endMinute: Int
    var extraAgents: [String]
    var dialMinutes: Int

    static let `default` = Preferences(
        followAgents: true,
        scheduleEnabled: false,
        days: [2, 3, 4, 5, 6],
        startMinute: 9 * 60,
        endMinute: 18 * 60,
        extraAgents: [],
        dialMinutes: 60
    )

    static func load(from data: Data?) -> Preferences {
        guard let data, let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return .default
        }
        return decoded.sanitized()
    }

    func sanitized() -> Preferences {
        var copy = self
        copy.days = Array(Set(copy.days.filter { (1...7).contains($0) })).sorted()
        copy.startMinute = min(24 * 60 - 1, max(0, copy.startMinute))
        copy.endMinute = min(24 * 60, max(0, copy.endMinute))
        copy.dialMinutes = DurationText.clamp(copy.dialMinutes)
        copy.extraAgents = copy.extraAgents
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return copy
    }
}

struct RuntimeState: Codable, Equatable, Sendable {
    var manualOn: Bool
    var timerEndsAt: Date?
    var timerMinutes: Int?
    var pausedAgents: Bool
    var pausedSchedule: Bool

    static let idle = RuntimeState(manualOn: false, timerEndsAt: nil, timerMinutes: nil, pausedAgents: false, pausedSchedule: false)

    static func load(from data: Data?) -> RuntimeState {
        guard let data, let decoded = try? JSONDecoder().decode(RuntimeState.self, from: data) else {
            return .idle
        }
        return decoded
    }
}

struct AwakePicture: Equatable, Sendable {
    var timerEndsAt: Date?
    var scheduleEndMinute: Int?
    var agents: [String]
    var manual: Bool

    var awake: Bool {
        timerEndsAt != nil || scheduleEndMinute != nil || !agents.isEmpty || manual
    }
}

enum Engine {
    static func normalize(now: Date, calendar: Calendar, prefs: Preferences, runtime: inout RuntimeState, agents: [String]) {
        if let end = runtime.timerEndsAt, end <= now {
            runtime.timerEndsAt = nil
            runtime.timerMinutes = nil
        }
        let scheduleLive = prefs.scheduleEnabled && scheduleEnd(prefs, now, calendar) != nil
        if !scheduleLive {
            runtime.pausedSchedule = false
        }
        if agents.isEmpty {
            runtime.pausedAgents = false
        }
    }

    static func picture(now: Date, calendar: Calendar, prefs: Preferences, runtime: RuntimeState, agents: [String]) -> AwakePicture {
        var picture = AwakePicture(timerEndsAt: nil, scheduleEndMinute: nil, agents: [], manual: runtime.manualOn)
        if let end = runtime.timerEndsAt, end > now {
            picture.timerEndsAt = end
        }
        if prefs.scheduleEnabled, !runtime.pausedSchedule {
            picture.scheduleEndMinute = scheduleEnd(prefs, now, calendar)
        }
        if prefs.followAgents, !runtime.pausedAgents {
            picture.agents = agents
        }
        return picture
    }

    static func scheduleEnd(_ prefs: Preferences, _ date: Date, _ calendar: Calendar) -> Int? {
        guard isScheduled(prefs, date, calendar) else { return nil }
        return prefs.endMinute
    }

    static func isScheduled(_ prefs: Preferences, _ date: Date, _ calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let start = prefs.startMinute
        let end = prefs.endMinute
        let days = Set(prefs.days)
        if days.isEmpty || start == end { return false }
        if start < end {
            return days.contains(weekday) && minute >= start && minute < end
        }
        if minute >= start && days.contains(weekday) { return true }
        let previous = weekday == 1 ? 7 : weekday - 1
        return minute < end && days.contains(previous)
    }

    static func sentence(picture: AwakePicture, now: Date, calendar: Calendar) -> String {
        guard picture.awake else { return "Asleep" }
        var parts: [String] = []
        if let until = picture.timerEndsAt {
            let seconds = max(0, until.timeIntervalSince(now))
            let minutes = max(1, Int(ceil(seconds / 60)))
            parts.append(DurationText.left(minutes))
        }
        if let end = picture.scheduleEndMinute {
            parts.append("on schedule until \(clock(end, calendar: calendar))")
        }
        if picture.agents.count == 1, let name = picture.agents.first {
            parts.append("\(name) is running")
        } else if picture.agents.count > 1 {
            parts.append("\(picture.agents.count) agents are running")
        }
        if picture.manual, parts.isEmpty {
            return "Awake until you turn it off"
        }
        if parts.isEmpty { return "Awake" }
        if parts.count == 1 { return "Awake, \(parts[0])" }
        return "Awake, \(parts[0]), \(parts.dropFirst().joined(separator: ", "))"
    }

    static func clock(_ minute: Int, calendar: Calendar) -> String {
        var parts = DateComponents()
        parts.hour = minute / 60
        parts.minute = minute % 60
        let date = calendar.date(from: parts) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func minute(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func date(minute: Int, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: Date())
        parts.hour = minute / 60
        parts.minute = minute % 60
        return calendar.date(from: parts) ?? Date()
    }
}

enum DurationText {
    static let minimum = 5
    static let maximum = 8 * 60
    static let detents = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]

    static func clamp(_ minutes: Int) -> Int {
        min(maximum, max(minimum, minutes))
    }

    static func nearestDetent(_ minutes: Int) -> Int {
        detents.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? 60
    }

    static func compact(_ minutes: Int) -> String {
        let minutes = max(0, minutes)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    static func words(_ minutes: Int) -> String {
        let minutes = max(0, minutes)
        if minutes < 60 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        let hourWord = hours == 1 ? "1 hour" : "\(hours) hours"
        if rest == 0 { return hourWord }
        let minuteWord = rest == 1 ? "1 minute" : "\(rest) minutes"
        return "\(hourWord) \(minuteWord)"
    }

    static func left(_ minutes: Int) -> String {
        "\(compact(minutes)) left"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(ceil(interval)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func parse(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return nil }
        if let colon = text.firstIndex(of: ":") {
            let hours = Int(text[..<colon]) ?? -1
            let mins = Int(text[text.index(after: colon)...]) ?? -1
            guard hours >= 0, mins >= 0, mins < 60 else { return nil }
            return clamp(hours * 60 + mins)
        }
        var hours = 0
        var mins = 0
        var matched = false
        if let range = text.range(of: #"\d+\s*h"#, options: .regularExpression) {
            hours = Int(text[range].filter(\.isNumber)) ?? 0
            matched = true
        }
        if let range = text.range(of: #"\d+\s*m"#, options: .regularExpression) {
            mins = Int(text[range].filter(\.isNumber)) ?? 0
            matched = true
        }
        if matched {
            let total = hours * 60 + mins
            return total == 0 ? nil : clamp(total)
        }
        if text.allSatisfy(\.isNumber), let value = Int(text) {
            return clamp(value)
        }
        return nil
    }
}

enum AgentMatch {
    static let known: [String: String] = [
        "claude": "Claude",
        "claude-code": "Claude",
        "codex": "Codex",
        "aider": "Aider",
        "gemini": "Gemini",
        "gemini-cli": "Gemini",
        "opencode": "OpenCode",
        "goose": "Goose",
        "crush": "Crush",
        "openclaw": "OpenClaw",
        "amp": "Amp",
        "cline": "Cline",
        "kilo": "Kilo",
        "kilocode": "Kilo",
        "qwen": "Qwen",
        "qwen-code": "Qwen",
        "kimi": "Kimi",
        "kimi-cli": "Kimi",
        "kiro-cli": "Kiro",
        "kiro-cli-chat": "Kiro",
        "auggie": "Auggie",
        "plandex": "Plandex",
        "openhands": "OpenHands",
        "gptme": "gptme",
        "junie": "Junie",
        "devin": "Devin",
        "interpreter": "Open Interpreter",
    ]

    // Package or install paths that name an agent even when a runner such as node starts it.
    static let signatures: [(fragment: String, name: String)] = [
        ("@anthropic-ai/claude-code", "Claude"),
        ("/share/claude/versions/", "Claude"),
        ("@openai/codex", "Codex"),
        ("@google/gemini-cli", "Gemini"),
        ("opencode-ai", "OpenCode"),
        ("@github/copilot", "Copilot"),
        ("@qwen-code/qwen-code", "Qwen"),
        ("@sourcegraph/amp", "Amp"),
        ("@augmentcode/auggie", "Auggie"),
        ("@kilocode/cli", "Kilo"),
        ("@mariozechner/pi-coding-agent", "Pi"),
        ("/.factory/bin/droid", "Droid"),
    ]

    private static let runners: Set<String> = [
        "node", "nodejs", "bun", "deno", "tsx", "ts-node", "npx", "bunx", "pnpx", "pnpm", "npm", "yarn",
        "uv", "uvx", "pipx", "ruby", "env",
    ]

    private static let subcommandWords: Set<String> = ["run", "exec", "dlx", "x", "tool"]
    private static let scriptSuffixes: Set<String> = ["js", "mjs", "cjs", "ts", "py"]

    // First arguments that start a helper, server, or one-shot command instead of real work.
    private static let idleWords: Set<String> = [
        "mcp", "app-server", "serve", "daemon", "login", "logout", "auth", "config", "doctor",
        "update", "upgrade", "install", "version", "help", "--version", "--help", "-h",
    ]

    static func names(in listing: String, extra: [String], executables: String = "") -> [String] {
        var seen = Set<String>()
        var found: [String] = []
        func add(_ name: String?) {
            guard let name, seen.insert(name).inserted else { return }
            found.append(name)
        }
        for line in listing.split(separator: "\n", omittingEmptySubsequences: true) {
            add(identify(command: String(line), extra: extra))
        }
        for line in executables.split(separator: "\n", omittingEmptySubsequences: true) {
            add(identify(executable: String(line), extra: extra))
        }
        return found
    }

    static func identify(command: String, extra: [String]) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("cursor-agent"), lower.contains("index.js agent"), !lower.contains("worker start"),
           !isSystemPath(lower) {
            return "Cursor"
        }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // A path with spaces inside an app bundle was cut short. The executable listing covers it.
        if lower.contains(".app/contents/"), !parts[0].lowercased().contains(".app/contents/") { return nil }
        return identify(executable: parts[0], arguments: Array(parts.dropFirst()), extra: extra)
    }

    // A bare executable path, as `ps -o comm` prints it. The path may contain spaces.
    static func identify(executable: String, extra: [String]) -> String? {
        let trimmed = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return identify(executable: trimmed, arguments: [], extra: extra)
    }

    private static func identify(executable: String, arguments: [String], extra: [String]) -> String? {
        let exe = executable.lowercased()
        if isSystemPath(exe) { return nil }
        // Desktop apps and their helper processes are not agents.
        if exe.hasPrefix("/applications/"), exe.contains(".app/contents/") { return nil }
        let base = lastComponent(exe)
        if base == "clamshelltoggle" || base == "agent" || base == "cursor" { return nil }

        let args = arguments.map { $0.lowercased() }
        if runners.contains(base) || base.hasPrefix("python") {
            let (index, script) = firstPositional(args)
            let tail = index.map { Array(args[($0 + 1)...]) } ?? []
            if isIdle(tail) { return nil }
            if let name = signature(in: ([exe] + args).joined(separator: " ")) { return name }
            guard let script else { return nil }
            return named(stripSuffix(lastComponent(script)), extra: extra)
        }
        if isIdle(args) { return nil }
        if let name = signature(in: exe) { return name }
        return named(base, extra: extra)
    }

    private static func isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/system/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/")
    }

    private static func named(_ base: String, extra: [String]) -> String? {
        if let name = known[base] { return name }
        for raw in extra {
            let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if needle.count < 2 || needle == "agent" || needle == "cursor" || needle == "node" { continue }
            if base == needle { return display(raw) }
        }
        return nil
    }

    private static func signature(in text: String) -> String? {
        signatures.first { text.contains($0.fragment) }?.name
    }

    private static func isIdle(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        return idleWords.contains(first)
    }

    // The script, package, or module a runner starts: `node x.js`, `python -m aider`, `uv run aider`.
    private static func firstPositional(_ args: [String]) -> (Int?, String?) {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "-m", index + 1 < args.count { return (index + 1, args[index + 1]) }
            if arg.hasPrefix("-") || subcommandWords.contains(arg) {
                index += 1
                continue
            }
            return (index, arg)
        }
        return (nil, nil)
    }

    private static func lastComponent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    private static func stripSuffix(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), scriptSuffixes.contains(String(name[name.index(after: dot)...])) else {
            return name
        }
        return String(name[..<dot])
    }

    private static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}

struct UpdateInfo: Equatable, Sendable {
    var version: String
    var build: Int

    static func parse(plist data: Data) -> UpdateInfo? {
        guard
            let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = object as? [String: Any],
            let version = dictionary["CFBundleShortVersionString"] as? String,
            let buildText = dictionary["CFBundleVersion"] as? String,
            let build = Int(buildText)
        else { return nil }
        return UpdateInfo(version: version, build: build)
    }

    func isNewer(than build: Int) -> Bool {
        self.build > build
    }
}

enum UpdateSchedule {
    static func isDue(last: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let last else { return true }
        if last > now { return true }
        return now.timeIntervalSince(last) >= interval
    }

    static func isBlocked(failedBuild: Int?, failedAt: Date?, build: Int, now: Date, wait: TimeInterval) -> Bool {
        guard let failedBuild, let failedAt, failedBuild == build else { return false }
        return failedAt <= now && now.timeIntervalSince(failedAt) < wait
    }
}
