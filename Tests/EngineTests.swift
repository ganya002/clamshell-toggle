import Foundation

@main
enum EngineTests {
    static func main() {
        testDuration()
        testSchedule()
        testPicture()
        testAgents()
        print("ok")
    }

    static func testDuration() {
        expect(DurationText.parse("90") == 90, "bare minutes")
        expect(DurationText.parse("2h") == 120, "hours")
        expect(DurationText.parse("1h 30m") == 90, "hours and minutes")
        expect(DurationText.parse("1h30m") == 90, "compact hours and minutes")
        expect(DurationText.parse("1:30") == 90, "clock")
        expect(DurationText.parse("4h") == 240, "four hours")
        expect(DurationText.parse("1m") == 5, "clamped up")
        expect(DurationText.parse("20h") == 480, "clamped down")
        expect(DurationText.parse("nope") == nil, "reject words")
        expect(DurationText.compact(120) == "2h", "compact hours")
        expect(DurationText.compact(90) == "1h 30m", "compact mixed")
        expect(DurationText.nearestDetent(70) == 60, "nearest hour")
        expect(DurationText.nearestDetent(100) == 90, "nearest ninety")
    }

    static func testSchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let mondayMorning = date(calendar, year: 2026, month: 10, day: 12, hour: 10, minute: 0)
        let mondayNight = date(calendar, year: 2026, month: 10, day: 12, hour: 23, minute: 0)
        let tuesdayEarly = date(calendar, year: 2026, month: 10, day: 13, hour: 6, minute: 0)
        let sunday = date(calendar, year: 2026, month: 10, day: 11, hour: 10, minute: 0)

        var prefs = Preferences.default
        prefs.days = [2]
        prefs.startMinute = 9 * 60
        prefs.endMinute = 18 * 60
        expect(Engine.isScheduled(prefs, mondayMorning, calendar), "monday inside")
        expect(!Engine.isScheduled(prefs, sunday, calendar), "sunday outside")
        expect(!Engine.isScheduled(prefs, mondayNight, calendar), "monday after hours")

        prefs.startMinute = 22 * 60
        prefs.endMinute = 7 * 60
        expect(Engine.isScheduled(prefs, mondayNight, calendar), "overnight start")
        expect(Engine.isScheduled(prefs, tuesdayEarly, calendar), "overnight spill")
        expect(!Engine.isScheduled(prefs, mondayMorning, calendar), "overnight gap")
    }

    static func testPicture() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(calendar, year: 2026, month: 10, day: 12, hour: 12, minute: 0)
        var prefs = Preferences.default
        prefs.followAgents = true
        prefs.scheduleEnabled = false
        var runtime = RuntimeState.idle

        var picture = Engine.picture(now: now, calendar: calendar, prefs: prefs, runtime: runtime, agents: ["Cursor"])
        expect(picture.awake && picture.agents == ["Cursor"], "agent holds awake")

        runtime.pausedAgents = true
        picture = Engine.picture(now: now, calendar: calendar, prefs: prefs, runtime: runtime, agents: ["Cursor"])
        expect(!picture.awake, "paused agent stays asleep")

        runtime.timerEndsAt = now.addingTimeInterval(600)
        picture = Engine.picture(now: now, calendar: calendar, prefs: prefs, runtime: runtime, agents: ["Cursor"])
        expect(picture.awake && picture.timerEndsAt != nil, "timer overrides pause")

        runtime.pausedAgents = true
        runtime.timerEndsAt = now.addingTimeInterval(-10)
        Engine.normalize(now: now, calendar: calendar, prefs: prefs, runtime: &runtime, agents: [])
        expect(runtime.timerEndsAt == nil && runtime.pausedAgents == false, "idle clears pause and expired timer")

        runtime = RuntimeState.idle
        runtime.manualOn = true
        picture = Engine.picture(now: now, calendar: calendar, prefs: prefs, runtime: runtime, agents: [])
        expect(picture.awake && picture.manual, "manual hold")
        expect(Engine.sentence(picture: picture, now: now, calendar: calendar) == "Awake until you turn it off", "manual sentence")
    }

    static func testAgents() {
        let worker = "/Users/gabbo/Library/Application Support/Cursor/agent-cli/cursor-agent --use-system-ca /tmp/index.js --api-key secret worker start --worker-dir /tmp"
        let active = "/Users/gabbo/.local/bin/agent --use-system-ca /Users/gabbo/.local/share/cursor-agent/versions/x/index.js agent"
        let claude = "/Users/gabbo/.local/bin/claude"
        let system = "/System/Library/CoreServices/WiFiAgent.app/Contents/MacOS/WiFiAgent"
        let teams = "/Applications/Microsoft Teams.app/Contents/MacOS/Teams --type=renderer copilot"
        let listing = [worker, active, claude, system, teams].joined(separator: "\n")
        let names = AgentMatch.names(in: listing, extra: [])
        expect(names == ["Cursor", "Claude"], "detected \(names)")
        expect(AgentMatch.identify(command: "/opt/homebrew/bin/codex", extra: []) == "Codex", "codex")
        expect(AgentMatch.identify(command: "/usr/local/bin/mytool", extra: ["mytool"]) == "Mytool", "extra name")
        expect(AgentMatch.identify(command: "/usr/local/bin/node server.js", extra: ["node"]) == nil, "node is too broad")
    }

    static func date(_ calendar: Calendar, year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("fail: \(message)\n", stderr)
            exit(1)
        }
    }
}
