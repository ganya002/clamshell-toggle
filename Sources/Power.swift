import Foundation

enum PowerError: Error, CustomStringConvertible, Equatable {
    case launch(String)
    case denied(String)

    var description: String {
        switch self {
        case .launch(let detail): detail
        case .denied(let detail): detail
        }
    }
}

enum Power {
    static func sleepDisabled() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.range(of: "SleepDisabled[[:space:]]+1", options: .regularExpression) != nil
    }

    static func setSleepDisabled(_ disabled: Bool) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "disablesleep", disabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw PowerError.launch(error.localizedDescription)
        }
        let detailData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let detail = String(data: detailData, encoding: .utf8) ?? ""
            throw PowerError.denied(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

final class PowerGate: @unchecked Sendable {
    private let queue = DispatchQueue(label: "clamshell.power")
    private var applied: Bool?

    func sync(to disabled: Bool) throws {
        try queue.sync {
            if applied == disabled { return }
            if Power.sleepDisabled() == disabled {
                applied = disabled
                return
            }
            try Power.setSleepDisabled(disabled)
            applied = disabled
        }
    }
}

struct BatteryStatus: Equatable, Sendable {
    var source: String
    var percentage: Int?
    var onBattery: Bool
}

extension Power {
    static func battery() -> BatteryStatus {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            return BatteryStatus(source: "Unknown", percentage: nil, onBattery: false)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return BatteryStatus(source: "Unknown", percentage: nil, onBattery: false)
        }
        let onBattery = text.contains("Battery Power")
        let source = onBattery ? "Battery" : (text.contains("AC Power") ? "Power Adapter" : "Unknown")
        var percentage: Int?
        if let match = text.range(of: #"[0-9]{1,3}%"#, options: .regularExpression) {
            percentage = Int(text[match].dropLast())
        }
        return BatteryStatus(source: source, percentage: percentage, onBattery: onBattery)
    }
}

enum AgentScan {
    static func current(extra: [String]) -> [String] {
        let commands = listing(column: "command=")
        let executables = listing(column: "comm=")
        return AgentMatch.names(in: commands, extra: extra, executables: executables)
    }

    private static func listing(column: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", column]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
