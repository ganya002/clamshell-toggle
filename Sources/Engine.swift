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
        "opencode": "OpenCode",
        "goose": "Goose",
        "crush": "Crush",
        "openclaw": "OpenClaw",
        "amp": "Amp",
    ]

    static func names(in listing: String, extra: [String]) -> [String] {
        var seen = Set<String>()
        var found: [String] = []
        for line in listing.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let name = identify(command: String(line), extra: extra), seen.insert(name).inserted else { continue }
            found.append(name)
        }
        return found
    }

    static func identify(command: String, extra: [String]) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("/System/") || trimmed.hasPrefix("/usr/libexec/") || trimmed.hasPrefix("/usr/sbin/") {
            return nil
        }
        let lower = trimmed.lowercased()
        if lower.contains("cursor-agent"), lower.contains("index.js agent"), !lower.contains("worker start") {
            return "Cursor"
        }
        let token = firstToken(trimmed)
        let base = URL(fileURLWithPath: token).lastPathComponent.lowercased()
        if base == "clamshelltoggle" || base == "agent" || base == "cursor" { return nil }
        if let name = known[base] { return name }
        for raw in extra {
            let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if needle.count < 2 || needle == "agent" || needle == "cursor" || needle == "node" { continue }
            if base == needle { return display(raw) }
        }
        return nil
    }

    private static func firstToken(_ command: String) -> String {
        if let space = command.firstIndex(of: " ") {
            return String(command[..<space])
        }
        return command
    }

    private static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }
}
