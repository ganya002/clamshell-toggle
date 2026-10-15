import AppKit

enum UpdateConfig {
    static let repo = "ganya002/clamshell-toggle"
    static let infoURL = URL(string: "https://raw.githubusercontent.com/\(repo)/main/Resources/Info.plist")!
    static let sourceURL = URL(string: "https://codeload.github.com/\(repo)/tar.gz/refs/heads/main")!
    static let checkInterval: TimeInterval = 6 * 60 * 60
    static let retryInterval: TimeInterval = 15 * 60
    static let failureWait: TimeInterval = 24 * 60 * 60
}

struct UpdateError: Error {
    var message: String
    init(_ message: String) { self.message = message }
}

enum UpdateCheck: Equatable {
    case upToDate(String)
    case available(UpdateInfo)
    case failed(String)
    case busy
}

@MainActor
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case available(UpdateInfo)
        case installing(UpdateInfo)
        case ready(UpdateInfo)
        case failed(String)
    }

    private(set) var state = State.idle {
        didSet { if state != oldValue { onChange?() } }
    }

    var onChange: (() -> Void)?
    var canRelaunch: () -> Bool = { true }
    var willRelaunch: (() -> Void)?
    var didFailRelaunch: (() -> Void)?

    var automatic: Bool {
        get { defaults.object(forKey: Key.automatic) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.automatic) }
    }

    static var appURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/Clamshell Toggle.app")
    }

    // Updates only work for the copy that install.sh puts in ~/Applications.
    static var supported: Bool {
        guard !CommandLine.arguments.contains("--preview") else { return false }
        return Bundle.main.bundleURL.resolvingSymlinksInPath().path == appURL.resolvingSymlinksInPath().path
    }

    private let runningBuild: Int
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var busy = false
    private var relaunching = false
    private var retryAt = Date.distantPast

    init() {
        // Read once. The bundle on disk changes after an update, but this process does not.
        runningBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    func start() {
        guard Self.supported, timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if case .ready = state {
            if canRelaunch() { relaunch() }
            return
        }
        guard automatic, !busy else { return }
        let now = Date()
        if case .available(let info) = state {
            if !isBlocked(info, now: now) {
                Task { _ = await install(info) }
            }
            return
        }
        guard now >= retryAt else { return }
        let last = defaults.object(forKey: Key.lastCheck) as? Date
        guard UpdateSchedule.isDue(last: last, now: now, interval: UpdateConfig.checkInterval) else { return }
        Task { _ = await check() }
    }

    func check() async -> UpdateCheck {
        if case .ready = state { return .busy }
        guard !busy else { return .busy }
        busy = true
        defer { busy = false }
        let before = state
        state = .checking
        do {
            let request = URLRequest(url: UpdateConfig.infoURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let info = UpdateInfo.parse(plist: data) else {
                throw UpdateError("GitHub sent an answer that this app cannot read.")
            }
            defaults.set(Date(), forKey: Key.lastCheck)
            if info.isNewer(than: runningBuild) {
                state = .available(info)
                return .available(info)
            }
            state = .idle
            return .upToDate(info.version)
        } catch {
            retryAt = Date().addingTimeInterval(UpdateConfig.retryInterval)
            state = before
            return .failed(Self.describe(error))
        }
    }

    // Builds the new version and swaps it into ~/Applications. Returns an error message, or nil on success.
    func install(_ info: UpdateInfo) async -> String? {
        guard !busy else { return "An update is already running." }
        busy = true
        defer { busy = false }
        state = .installing(info)
        let running = runningBuild
        let appURL = Self.appURL
        do {
            let built = try await Task.detached(priority: .utility) {
                try await UpdateBuild.run(expected: info, runningBuild: running, appURL: appURL)
            }.value
            defaults.removeObject(forKey: Key.failedBuild)
            defaults.removeObject(forKey: Key.failedAt)
            state = .ready(built)
            return nil
        } catch {
            let message = Self.describe(error)
            defaults.set(info.build, forKey: Key.failedBuild)
            defaults.set(Date(), forKey: Key.failedAt)
            state = .failed(message)
            return message
        }
    }

    // Starts the new copy, then quits this one.
    func relaunch() {
        guard case .ready = state, !relaunching else { return }
        relaunching = true
        willRelaunch?()
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Self.appURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                relaunching = false
                didFailRelaunch?()
                state = .failed("The new version is installed, but it did not start. Open Clamshell Toggle from the Applications folder.")
            }
        }
    }

    private func isBlocked(_ info: UpdateInfo, now: Date) -> Bool {
        UpdateSchedule.isBlocked(
            failedBuild: defaults.object(forKey: Key.failedBuild) as? Int,
            failedAt: defaults.object(forKey: Key.failedAt) as? Date,
            build: info.build,
            now: now,
            wait: UpdateConfig.failureWait
        )
    }

    private static func describe(_ error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }

    private enum Key {
        static let automatic = "clamshell.update.automatic"
        static let lastCheck = "clamshell.update.lastCheck"
        static let failedBuild = "clamshell.update.failedBuild"
        static let failedAt = "clamshell.update.failedAt"
    }
}

// Downloads the source, runs the installer in update mode, and checks what landed on disk.
enum UpdateBuild {
    static func run(expected: UpdateInfo, runningBuild: Int, appURL: URL) async throws -> UpdateInfo {
        let files = FileManager.default
        let work = files.temporaryDirectory.appendingPathComponent("clamshell-update-\(UUID().uuidString)", isDirectory: true)
        let extract = work.appendingPathComponent("extract", isDirectory: true)
        try files.createDirectory(at: extract, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: UpdateConfig.sourceURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("The download from GitHub failed.")
        }
        let archive = work.appendingPathComponent("source.tgz")
        try files.moveItem(at: downloaded, to: archive)

        let untar = try await exec("/usr/bin/tar", ["-xzf", archive.path, "-C", extract.path], in: work, log: nil)
        guard untar == 0 else { throw UpdateError("The download could not be unpacked.") }

        let roots = try files.contentsOfDirectory(at: extract, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard roots.count == 1, let root = roots.first else {
            throw UpdateError("The download has an unexpected layout.")
        }
        let script = root.appendingPathComponent("install.sh")
        let plist = root.appendingPathComponent("Resources/Info.plist")
        guard files.fileExists(atPath: script.path), let data = try? Data(contentsOf: plist), let source = UpdateInfo.parse(plist: data) else {
            throw UpdateError("The download is missing files.")
        }
        guard source.build >= expected.build, source.isNewer(than: runningBuild) else {
            throw UpdateError("The download is not newer than this version.")
        }

        let logURL = work.appendingPathComponent("install.log")
        files.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let status: Int32
        do {
            status = try await exec("/bin/bash", [script.path, "--update"], in: work, log: log)
            try? log.close()
        } catch {
            try? log.close()
            throw error
        }
        guard status == 0 else {
            throw UpdateError("The build failed.\n" + tail(of: logURL))
        }

        let installedPlist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let installedData = try? Data(contentsOf: installedPlist),
              let installed = UpdateInfo.parse(plist: installedData),
              installed.build == source.build else {
            throw UpdateError("The new version did not land in the Applications folder.")
        }
        return installed
    }

    private static func exec(_ path: String, _ arguments: [String], in directory: URL, log: FileHandle?) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = log ?? FileHandle.nullDevice
            process.standardError = log ?? FileHandle.nullDevice
            process.qualityOfService = .utility
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func tail(of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(8)
        return lines.joined(separator: "\n")
    }
}
