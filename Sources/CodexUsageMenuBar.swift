import AppKit
import Foundation
import ServiceManagement

private enum L10n {
    static func string(_ key: String, fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: string(key, fallback: fallback), arguments: arguments)
    }
}

private enum AppError: LocalizedError {
    case codexNotFound
    case serverStopped
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return L10n.string(
                "error.codex_not_found",
                fallback: "Codex CLI was not found. Install the ChatGPT or Codex app."
            )
        case .serverStopped:
            return L10n.string(
                "error.server_stopped",
                fallback: "The connection to Codex App Server ended."
            )
        case .invalidResponse:
            return L10n.string(
                "error.invalid_response",
                fallback: "Codex returned an invalid response."
            )
        case .server(let message):
            return message
        }
    }
}

private enum ApplicationRelocator {
    private static let appName = "Codex Usage.app"

    static var destinationDirectory: URL {
        if let overridePath = ProcessInfo.processInfo.environment["CODEX_USAGE_APPLICATIONS_DIR"] {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    static var destinationURL: URL {
        destinationDirectory.appendingPathComponent(appName, isDirectory: true)
    }

    static func isRunningFromApplications() -> Bool {
        let parent = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let userApplications = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return parent == systemApplications || parent == userApplications
    }

    static func offerMoveAndRelaunch() -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app",
              !isRunningFromApplications() else { return false }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string(
            "installer.move_title",
            fallback: "Move to the Applications folder?"
        )
        let messageKey = FileManager.default.fileExists(atPath: destinationURL.path)
            ? "installer.replace_message"
            : "installer.move_message"
        let messageFallback = FileManager.default.fileExists(atPath: destinationURL.path)
            ? "Replace the existing Codex Usage app, move this copy to Applications, and open it."
            : "Move Codex Usage to the Applications folder and open it."
        alert.informativeText = L10n.string(messageKey, fallback: messageFallback)
        alert.addButton(withTitle: L10n.string("installer.move_and_open", fallback: "Move and Open"))
        alert.addButton(withTitle: L10n.string("installer.open_here", fallback: "Open Here"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.setActivationPolicy(.accessory)
            return false
        }

        do {
            let installedURL = try install(to: destinationDirectory)
            try launch(installedURL)
            return true
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = L10n.string(
                "installer.failure_title",
                fallback: "Could not move the app to Applications"
            )
            failure.informativeText = L10n.format(
                "installer.failure_message",
                fallback: "The app will continue running from this location.\n\n%@",
                error.localizedDescription
            )
            failure.addButton(withTitle: L10n.string("button.ok", fallback: "OK"))
            failure.runModal()
            NSApp.setActivationPolicy(.accessory)
            return false
        }
    }

    @discardableResult
    static func install(to directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = Bundle.main.bundleURL
        let destination = directory.appendingPathComponent(appName, isDirectory: true)
        let identifier = UUID().uuidString
        let staging = directory.appendingPathComponent(".Codex Usage.installing-\(identifier).app", isDirectory: true)
        let backup = directory.appendingPathComponent(".Codex Usage.backup-\(identifier).app", isDirectory: true)

        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }

        try fileManager.copyItem(at: source, to: staging)

        let hasExistingApp = fileManager.fileExists(atPath: destination.path)
        if hasExistingApp {
            try fileManager.moveItem(at: destination, to: backup)
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if hasExistingApp, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }

        if hasExistingApp {
            try? fileManager.removeItem(at: backup)
        }
        return destination
    }

    private static func launch(_ applicationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", applicationURL.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "jp.codex.usage-menubar.install",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.string(
                        "installer.launch_failed",
                        fallback: "The installed app could not be opened."
                    )
                ]
            )
        }
    }
}

private struct LimitWindow {
    private enum Kind {
        case fiveHour
        case weekly
    }

    let usedPercent: Int
    let resetsAt: Date?
    let durationMinutes: Int?

    init?(json: [String: Any]?) {
        guard let json, let usedPercent = json["usedPercent"] as? Int else { return nil }
        self.usedPercent = usedPercent
        if let epoch = json["resetsAt"] as? Int {
            self.resetsAt = Date(timeIntervalSince1970: TimeInterval(epoch))
        } else {
            self.resetsAt = nil
        }
        self.durationMinutes = json["windowDurationMins"] as? Int
    }

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }

    fileprivate var isFiveHour: Bool {
        kind == .fiveHour
    }

    fileprivate var isWeekly: Bool {
        kind == .weekly
    }

    private var kind: Kind? {
        guard let durationMinutes else { return nil }
        return durationMinutes < 1_440 ? .fiveHour : .weekly
    }
}

private struct UsageSnapshot {
    let fiveHour: LimitWindow?
    let weekly: LimitWindow?
    let planType: String?
    let updatedAt: Date

    func statusTitle(dailyUsage: DailyUsageState, hourlyUsage: TrackedUsageState) -> String {
        var components: [String] = []
        if let fiveHour {
            components.append("5h \(fiveHour.remainingPercent)%")
        }
        if let weekly {
            components.append("W \(weekly.remainingPercent)%")
        }
        switch dailyUsage {
        case .unavailable:
            break
        case .usage(let percent, let isPartial):
            components.append("1D \(percent)%\(isPartial ? "+" : "")")
        }
        switch hourlyUsage {
        case .unavailable:
            break
        case .collecting:
            components.append("1H …")
        case .usage(let percent):
            components.append("1H \(percent)%")
        }
        return components.isEmpty ? "Codex —" : components.joined(separator: "  ")
    }

    init(result: [String: Any]) throws {
        guard let rateLimits = result["rateLimits"] as? [String: Any] else {
            throw AppError.invalidResponse
        }
        let rawPrimary = LimitWindow(json: rateLimits["primary"] as? [String: Any])
        let rawSecondary = LimitWindow(json: rateLimits["secondary"] as? [String: Any])
        let windows = [rawPrimary, rawSecondary].compactMap { $0 }

        fiveHour = windows.first(where: \.isFiveHour)
            ?? (rawPrimary?.durationMinutes == nil ? rawPrimary : nil)
        weekly = windows.first(where: \.isWeekly)
            ?? (rawSecondary?.durationMinutes == nil ? rawSecondary : nil)
        planType = rateLimits["planType"] as? String
        updatedAt = Date()
    }
}

private enum TrackedUsageState {
    case unavailable
    case collecting
    case usage(Int)
}

private enum DailyUsageState {
    case unavailable
    case usage(Int, isPartial: Bool)
}

private struct UsageSample: Codable {
    let recordedAt: TimeInterval
    let usedPercent: Int
    let durationMinutes: Int?
    let resetsAt: TimeInterval?

    func belongsToSameWindow(as other: UsageSample) -> Bool {
        durationMinutes == other.durationMinutes && resetsAt == other.resetsAt
    }
}

private struct UsageHistory: Codable {
    private(set) var samples: [UsageSample] = []

    mutating func record(_ window: LimitWindow, at date: Date) -> Int? {
        let current = UsageSample(
            recordedAt: date.timeIntervalSince1970,
            usedPercent: window.usedPercent,
            durationMinutes: window.durationMinutes,
            resetsAt: window.resetsAt?.timeIntervalSince1970
        )
        samples.append(current)

        let retentionStart = date.addingTimeInterval(-172_800).timeIntervalSince1970
        samples.removeAll { $0.recordedAt < retentionStart }

        let oneHourAgo = date.addingTimeInterval(-3_600).timeIntervalSince1970
        let oldestAcceptableBaseline = oneHourAgo - 300
        guard let baseline = samples
            .filter({
                $0.recordedAt >= oldestAcceptableBaseline
                    && $0.recordedAt <= oneHourAgo
                    && $0.belongsToSameWindow(as: current)
            })
            .max(by: { $0.recordedAt < $1.recordedAt }) else {
            return nil
        }
        guard current.usedPercent >= baseline.usedPercent else { return nil }
        return current.usedPercent - baseline.usedPercent
    }

    func usageToday(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int? {
        guard let current = samples.last else { return nil }
        let startOfDay = calendar.startOfDay(for: date).timeIntervalSince1970

        let baseline: UsageSample
        if let exact = samples
            .last(where: { $0.recordedAt == startOfDay }) {
            baseline = UsageSample(
                recordedAt: startOfDay,
                usedPercent: exact.usedPercent,
                durationMinutes: exact.durationMinutes,
                resetsAt: exact.resetsAt
            )
        } else {
            guard let before = samples
                .filter({ $0.recordedAt < startOfDay })
                .max(by: { $0.recordedAt < $1.recordedAt }),
                  let after = samples
                .filter({
                    $0.recordedAt > startOfDay
                        && $0.recordedAt <= current.recordedAt
                })
                .min(by: { $0.recordedAt < $1.recordedAt }) else {
                return nil
            }

            if before.belongsToSameWindow(as: after),
               before.usedPercent == after.usedPercent {
                baseline = UsageSample(
                    recordedAt: startOfDay,
                    usedPercent: after.usedPercent,
                    durationMinutes: after.durationMinutes,
                    resetsAt: after.resetsAt
                )
            } else if before.resetsAt == startOfDay,
                !before.belongsToSameWindow(as: after) {
                baseline = UsageSample(
                    recordedAt: startOfDay,
                    usedPercent: 0,
                    durationMinutes: after.durationMinutes,
                    resetsAt: after.resetsAt
                )
            } else {
                return nil
            }
        }

        let daySamples = samples
            .filter({
                $0.recordedAt > startOfDay
                    && $0.recordedAt <= current.recordedAt
            })
            .sorted(by: { $0.recordedAt < $1.recordedAt })
        var previous = baseline
        for sample in daySamples {
            guard sample.belongsToSameWindow(as: previous),
                  sample.usedPercent >= previous.usedPercent else {
                return nil
            }
            previous = sample
        }

        guard current.belongsToSameWindow(as: baseline),
              current.usedPercent >= baseline.usedPercent else {
            return nil
        }
        return current.usedPercent - baseline.usedPercent
    }

    func partialUsageToday(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        let startOfDay = calendar.startOfDay(for: date).timeIntervalSince1970
        let todaySamples = samples
            .filter({
                $0.recordedAt >= startOfDay
                    && $0.recordedAt <= date.timeIntervalSince1970
            })
            .sorted(by: { $0.recordedAt < $1.recordedAt })
        guard let first = todaySamples.first else { return 0 }

        func windowStartedAt(_ sample: UsageSample) -> TimeInterval? {
            guard let resetsAt = sample.resetsAt,
                  let durationMinutes = sample.durationMinutes else {
                return nil
            }
            return resetsAt - TimeInterval(durationMinutes * 60)
        }

        func windowStartedToday(_ sample: UsageSample) -> Bool {
            guard let windowStartedAt = windowStartedAt(sample) else { return false }
            return windowStartedAt >= startOfDay && windowStartedAt <= sample.recordedAt
        }

        var completedSegments = 0
        var currentSegment = windowStartedToday(first) ? first.usedPercent : 0
        var previous = first
        for sample in todaySamples.dropFirst() {
            if sample.belongsToSameWindow(as: previous) {
                if sample.usedPercent >= previous.usedPercent {
                    currentSegment += sample.usedPercent - previous.usedPercent
                } else {
                    currentSegment = windowStartedToday(sample) ? sample.usedPercent : 0
                }
            } else if let windowStartedAt = windowStartedAt(sample),
                      windowStartedAt >= startOfDay,
                      windowStartedAt > previous.recordedAt,
                      windowStartedAt <= sample.recordedAt {
                completedSegments += currentSegment
                currentSegment = sample.usedPercent
            } else {
                completedSegments = 0
                currentSegment = windowStartedToday(sample) ? sample.usedPercent : 0
            }
            previous = sample
        }
        return completedSegments + currentSegment
    }
}

private struct DailyUsage {
    let percent: Int
    let isPartial: Bool
}

private struct TrackedUsage {
    let hourlyPercent: Int?
    let dailyUsage: DailyUsage?
}

private final class UsageTracker {
    // Keep the original key so users retain history when upgrading from 1.4.x.
    private static let storageKey = "hourlyUsageHistory.v1"

    private let defaults: UserDefaults
    private var history: UsageHistory

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? PropertyListDecoder().decode(UsageHistory.self, from: data) {
            history = decoded
        } else {
            history = UsageHistory()
        }
    }

    func record(
        _ window: LimitWindow?,
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> TrackedUsage {
        guard let window else {
            return TrackedUsage(hourlyPercent: nil, dailyUsage: nil)
        }
        let hourlyPercent = history.record(window, at: date)
        let dailyUsage: DailyUsage
        if let exactPercent = history.usageToday(at: date, calendar: calendar) {
            dailyUsage = DailyUsage(percent: exactPercent, isPartial: false)
        } else {
            dailyUsage = DailyUsage(
                percent: history.partialUsageToday(at: date, calendar: calendar),
                isPartial: true
            )
        }
        if let data = try? PropertyListEncoder().encode(history) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return TrackedUsage(
            hourlyPercent: hourlyPercent,
            dailyUsage: dailyUsage
        )
    }
}

private final class CodexAppServerClient {
    typealias Completion = (Result<UsageSnapshot, Error>) -> Void

    private enum State {
        case stopped
        case initializing
        case ready
    }

    private let queue = DispatchQueue(label: "jp.codex.usage-menubar.app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var buffer = Data()
    private var nextRequestID = 1
    private var state: State = .stopped
    private var callbacks: [Int: (Result<[String: Any], Error>) -> Void] = [:]
    private var pendingUsageRequests: [Completion] = []

    func fetchUsage(completion: @escaping Completion) {
        queue.async {
            switch self.state {
            case .stopped:
                self.pendingUsageRequests.append(completion)
                self.startServer()
            case .initializing:
                self.pendingUsageRequests.append(completion)
            case .ready:
                self.requestUsage(completion: completion)
            }
        }
    }

    func stop() {
        queue.sync {
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            self.process?.terminationHandler = nil
            if self.process?.isRunning == true {
                self.process?.terminate()
            }
            self.process = nil
            self.inputPipe = nil
            self.outputPipe = nil
            self.state = .stopped
        }
    }

    private func startServer() {
        guard let executable = Self.findCodexExecutable() else {
            failAll(with: AppError.codexNotFound)
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.handleTermination() }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            self.state = .initializing
            sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "codex-usage-app",
                        "title": "Codex Usage App",
                        "version": "1.5.2"
                    ]
                ]
            ) { result in
                switch result {
                case .success:
                    self.sendNotification(method: "initialized")
                    self.state = .ready
                    let pending = self.pendingUsageRequests
                    self.pendingUsageRequests.removeAll()
                    for completion in pending {
                        self.requestUsage(completion: completion)
                    }
                case .failure(let error):
                    self.failAll(with: error)
                }
            }
        } catch {
            failAll(with: error)
        }
    }

    private func requestUsage(completion: @escaping Completion) {
        sendRequest(method: "account/rateLimits/read", params: nil) { result in
            switch result {
            case .success(let json):
                do {
                    completion(.success(try UsageSnapshot(result: json)))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func sendRequest(
        method: String,
        params: Any?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let id = nextRequestID
        nextRequestID += 1
        callbacks[id] = completion
        var payload: [String: Any] = ["id": id, "method": method]
        if let params { payload["params"] = params }
        writeJSON(payload)
    }

    private func sendNotification(method: String) {
        writeJSON(["method": method])
    }

    private func writeJSON(_ value: [String: Any]) {
        guard let handle = inputPipe?.fileHandleForWriting,
              var data = try? JSONSerialization.data(withJSONObject: value) else { return }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            failAll(with: error)
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int,
                  let callback = callbacks.removeValue(forKey: id) else { continue }

            if let errorObject = object["error"] as? [String: Any] {
                let message = errorObject["message"] as? String
                    ?? L10n.string("error.server", fallback: "Codex App Server error")
                callback(.failure(AppError.server(message)))
            } else if let result = object["result"] as? [String: Any] {
                callback(.success(result))
            } else {
                callback(.failure(AppError.invalidResponse))
            }
        }
    }

    private func handleTermination() {
        guard state != .stopped else { return }
        process = nil
        inputPipe = nil
        outputPipe = nil
        state = .stopped
        failAll(with: AppError.serverStopped)
    }

    private func failAll(with error: Error) {
        let requestCallbacks = callbacks.values
        callbacks.removeAll()
        let usageCallbacks = pendingUsageRequests
        pendingUsageRequests.removeAll()
        state = .stopped
        requestCallbacks.forEach { $0(.failure(error)) }
        usageCallbacks.forEach { $0(.failure(error)) }
    }

    private static func findCodexExecutable() -> URL? {
        if let overridePath = ProcessInfo.processInfo.environment["CODEX_PATH"],
           FileManager.default.isExecutableFile(atPath: overridePath) {
            return URL(fileURLWithPath: overridePath)
        }

        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/ChatGPT.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = CodexAppServerClient()
    private let usageTracker = UsageTracker()
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var snapshot: UsageSnapshot?
    private var hourlyUsage: TrackedUsageState = .unavailable
    private var dailyUsage: DailyUsageState = .unavailable
    private var errorMessage: String?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ApplicationRelocator.offerMoveAndRelaunch() {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Codex …"
        rebuildMenu()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        client.stop()
    }

    @objc private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        rebuildMenu()
        client.fetchUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    if let weekly = snapshot.weekly {
                        let trackedUsage = self.usageTracker.record(
                            weekly,
                            at: snapshot.updatedAt
                        )
                        self.hourlyUsage = trackedUsage.hourlyPercent
                            .map(TrackedUsageState.usage) ?? .collecting
                        if let dailyUsage = trackedUsage.dailyUsage {
                            self.dailyUsage = .usage(
                                dailyUsage.percent,
                                isPartial: dailyUsage.isPartial
                            )
                        } else {
                            self.dailyUsage = .unavailable
                        }
                    } else {
                        self.hourlyUsage = .unavailable
                        self.dailyUsage = .unavailable
                    }
                    self.snapshot = snapshot
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.updateStatusTitle()
                self.rebuildMenu()
            }
        }
    }

    private func updateStatusTitle() {
        guard let snapshot else {
            statusItem.button?.title = "Codex —"
            return
        }
        statusItem.button?.title = snapshot.statusTitle(
            dailyUsage: dailyUsage,
            hourlyUsage: hourlyUsage
        )
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(
            title: L10n.string("menu.title", fallback: "Codex Usage App"),
            action: nil,
            keyEquivalent: ""
        )
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        if let snapshot {
            switch dailyUsage {
            case .usage(let percent, let isPartial):
                addDisabled(
                    L10n.format(
                        isPartial ? "menu.today_usage_partial" : "menu.today_usage",
                        fallback: isPartial
                            ? "Today: Used at least %d%%"
                            : "Today: Used %d%%",
                        percent
                    ),
                    to: menu
                )
                menu.addItem(.separator())
            case .unavailable:
                break
            }
            switch hourlyUsage {
            case .usage(let percent):
                addDisabled(
                    L10n.format(
                        "menu.last_hour_usage",
                        fallback: "Last hour: Used %d%%",
                        percent
                    ),
                    to: menu
                )
                menu.addItem(.separator())
            case .collecting:
                addDisabled(
                    L10n.string(
                        "menu.last_hour_collecting",
                        fallback: "Last hour: Collecting data…"
                    ),
                    to: menu
                )
                menu.addItem(.separator())
            case .unavailable:
                break
            }
            if let fiveHour = snapshot.fiveHour {
                addWindow(
                    fiveHour,
                    fallbackName: L10n.string("window.five_hour", fallback: "5-hour limit"),
                    to: menu
                )
                menu.addItem(.separator())
            }
            if let weekly = snapshot.weekly {
                addWindow(
                    weekly,
                    fallbackName: L10n.string("window.weekly", fallback: "Weekly limit"),
                    to: menu
                )
                menu.addItem(.separator())
            }
            if let plan = snapshot.planType {
                addDisabled(
                    L10n.format("menu.plan", fallback: "Plan: %@", formatPlan(plan)),
                    to: menu
                )
            }
            addDisabled(
                L10n.format(
                    "menu.last_updated",
                    fallback: "Last updated: %@",
                    timeFormatter.string(from: snapshot.updatedAt)
                ),
                to: menu
            )
        } else {
            addDisabled(
                isRefreshing
                    ? L10n.string("menu.fetching", fallback: "Fetching usage…")
                    : L10n.string("menu.unavailable", fallback: "Usage unavailable"),
                to: menu
            )
        }

        if let errorMessage {
            menu.addItem(.separator())
            let errorItem = NSMenuItem(
                title: L10n.format("menu.error", fallback: "Error: %@", errorMessage),
                action: nil,
                keyEquivalent: ""
            )
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(
            title: L10n.string("menu.refresh", fallback: "Refresh Now"),
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing
        menu.addItem(refreshItem)

        if #available(macOS 13.0, *) {
            let launchItem = NSMenuItem(
                title: L10n.string("menu.launch_at_login", fallback: "Launch at Login"),
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            launchItem.target = self
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(launchItem)
        }

        let openItem = NSMenuItem(
            title: L10n.string("menu.open_chatgpt", fallback: "Open ChatGPT"),
            action: #selector(openChatGPT),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit", fallback: "Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func addWindow(_ window: LimitWindow?, fallbackName: String, to menu: NSMenu) {
        guard let window else {
            addDisabled("\(fallbackName): —", to: menu)
            return
        }
        let name: String
        if let minutes = window.durationMinutes, minutes == 300 {
            name = L10n.string("window.five_hour", fallback: "5-hour limit")
        } else if let minutes = window.durationMinutes, minutes == 10_080 {
            name = L10n.string("window.weekly", fallback: "Weekly limit")
        } else {
            name = fallbackName
        }
        addDisabled(
            L10n.format(
                "window.usage",
                fallback: "%@: Remaining %d%% (Used %d%%)",
                name,
                window.remainingPercent,
                window.usedPercent
            ),
            to: menu
        )
        if let reset = window.resetsAt {
            addDisabled(
                L10n.format(
                    "window.reset",
                    fallback: "Reset: %@",
                    resetFormatter.string(from: reset)
                ),
                indent: 1,
                to: menu
            )
        }
    }

    private func addDisabled(_ title: String, indent: Int = 0, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent
        menu.addItem(item)
    }

    private func formatPlan(_ value: String) -> String {
        switch value.lowercased() {
        case "prolite": return "Pro"
        case "plus": return "Plus"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return value
        }
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            rebuildMenu()
        } catch {
            showAlert(
                title: L10n.string(
                    "autostart.error_title",
                    fallback: "Could not change Launch at Login"
                ),
                message: L10n.format(
                    "autostart.error_message",
                    fallback: "Move the app to the Applications folder, then try again.\n\n%@",
                    error.localizedDescription
                )
            )
        }
    }

    @objc private func openChatGPT() {
        let paths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("button.ok", fallback: "OK"))
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter
    }()

    private lazy var resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")
        return formatter
    }()
}

@main
private enum CodexUsageMenuBarApp {
    static func main() {
        if CommandLine.arguments.contains("--localization-test") {
            print(
                "move_title="
                    + L10n.string(
                        "installer.move_title",
                        fallback: "Move to the Applications folder?"
                    )
            )
            print("refresh=" + L10n.string("menu.refresh", fallback: "Refresh Now"))
            print(
                "today_partial="
                    + L10n.format(
                        "menu.today_usage_partial",
                        fallback: "Today: Used at least %d%%",
                        3
                    )
            )
            print("quit=" + L10n.string("menu.quit", fallback: "Quit"))
            Foundation.exit(0)
        }

        if let testIndex = CommandLine.arguments.firstIndex(of: "--self-install-test"),
           CommandLine.arguments.indices.contains(testIndex + 1) {
            let destination = URL(
                fileURLWithPath: CommandLine.arguments[testIndex + 1],
                isDirectory: true
            )
            do {
                let installedURL = try ApplicationRelocator.install(to: destination)
                print("OK installed=\(installedURL.path)")
                Foundation.exit(0)
            } catch {
                fputs("ERROR \(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
        }

        if CommandLine.arguments.contains("--self-test") {
            let client = CodexAppServerClient()
            let semaphore = DispatchSemaphore(value: 0)
            var exitCode: Int32 = 1
            client.fetchUsage { result in
                switch result {
                case .success(let snapshot):
                    let fiveHour = snapshot.fiveHour?.remainingPercent.description ?? "—"
                    let weekly = snapshot.weekly?.remainingPercent.description ?? "—"
                    let hourlyState: TrackedUsageState = snapshot.weekly == nil
                        ? .unavailable
                        : .collecting
                    let dailyState: DailyUsageState = snapshot.weekly == nil
                        ? .unavailable
                        : .usage(0, isPartial: true)
                    let status = snapshot.statusTitle(
                        dailyUsage: dailyState,
                        hourlyUsage: hourlyState
                    )
                    print(
                        "OK status=\(status) "
                            + "5h_remaining=\(fiveHour)% weekly_remaining=\(weekly)%"
                    )
                    exitCode = 0
                case .failure(let error):
                    fputs("ERROR \(error.localizedDescription)\n", stderr)
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 20)
            client.stop()
            Foundation.exit(exitCode)
        }

        if CommandLine.arguments.contains("--rate-limit-parser-test") {
            do {
                let weeklyOnly = try UsageSnapshot(result: [
                    "rateLimits": [
                        "primary": [
                            "usedPercent": 32,
                            "windowDurationMins": 10_080
                        ],
                        "secondary": NSNull()
                    ]
                ])
                let bothWindows = try UsageSnapshot(result: [
                    "rateLimits": [
                        "primary": [
                            "usedPercent": 5,
                            "windowDurationMins": 300
                        ],
                        "secondary": [
                            "usedPercent": 31,
                            "windowDurationMins": 10_080
                        ]
                    ]
                ])
                guard weeklyOnly.fiveHour == nil,
                      weeklyOnly.weekly?.remainingPercent == 68,
                      weeklyOnly.statusTitle(
                          dailyUsage: .usage(0, isPartial: true),
                          hourlyUsage: .collecting
                      ) == "W 68%  1D 0%+  1H …",
                      weeklyOnly.statusTitle(
                          dailyUsage: .usage(7, isPartial: false),
                          hourlyUsage: .usage(3)
                      ) == "W 68%  1D 7%  1H 3%",
                      weeklyOnly.statusTitle(
                          dailyUsage: .usage(4, isPartial: true),
                          hourlyUsage: .usage(3)
                      ) == "W 68%  1D 4%+  1H 3%",
                      bothWindows.fiveHour?.remainingPercent == 95,
                      bothWindows.weekly?.remainingPercent == 69,
                      bothWindows.statusTitle(
                          dailyUsage: .usage(7, isPartial: false),
                          hourlyUsage: .usage(3)
                      ) == "5h 95%  W 69%  1D 7%  1H 3%",
                      weeklyOnly.statusTitle(
                          dailyUsage: .unavailable,
                          hourlyUsage: .unavailable
                      ) == "W 68%" else {
                    throw AppError.invalidResponse
                }
                print("OK rate-limit-window-classification")
                Foundation.exit(0)
            } catch {
                fputs("ERROR \(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
        }

        if CommandLine.arguments.contains("--usage-history-test") {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let reset = 1_800_604_800
            func weeklyWindow(usedPercent: Int, resetsAt: Int = reset) -> LimitWindow {
                LimitWindow(json: [
                    "usedPercent": usedPercent,
                    "windowDurationMins": 10_080,
                    "resetsAt": resetsAt
                ])!
            }

            var history = UsageHistory()
            let initial = history.record(weeklyWindow(usedPercent: 10), at: start)
            let halfHour = history.record(
                weeklyWindow(usedPercent: 12),
                at: start.addingTimeInterval(1_800)
            )
            let oneHour = history.record(
                weeklyWindow(usedPercent: 14),
                at: start.addingTimeInterval(3_600)
            )
            let ninetyMinutes = history.record(
                weeklyWindow(usedPercent: 15),
                at: start.addingTimeInterval(5_400)
            )
            let afterReset = history.record(
                weeklyWindow(usedPercent: 1, resetsAt: reset + 604_800),
                at: start.addingTimeInterval(7_200)
            )
            var staleHistory = UsageHistory()
            _ = staleHistory.record(weeklyWindow(usedPercent: 20), at: start)
            let afterNinetyMinuteGap = staleHistory.record(
                weeklyWindow(usedPercent: 25),
                at: start.addingTimeInterval(5_400)
            )
            var boundaryHistory = UsageHistory()
            _ = boundaryHistory.record(weeklyWindow(usedPercent: 20), at: start)
            let atSixtyFiveMinutes = boundaryHistory.record(
                weeklyWindow(usedPercent: 24),
                at: start.addingTimeInterval(3_900)
            )
            var outsideBoundaryHistory = UsageHistory()
            _ = outsideBoundaryHistory.record(weeklyWindow(usedPercent: 20), at: start)
            let afterSixtyFiveMinutes = outsideBoundaryHistory.record(
                weeklyWindow(usedPercent: 24),
                at: start.addingTimeInterval(3_901)
            )
            var resetWithoutTimestampHistory = UsageHistory()
            func weeklyWindowWithoutReset(usedPercent: Int) -> LimitWindow {
                LimitWindow(json: [
                    "usedPercent": usedPercent,
                    "windowDurationMins": 10_080
                ])!
            }
            _ = resetWithoutTimestampHistory.record(
                weeklyWindowWithoutReset(usedPercent: 90),
                at: start
            )
            let resetWithoutTimestamp = resetWithoutTimestampHistory.record(
                weeklyWindowWithoutReset(usedPercent: 1),
                at: start.addingTimeInterval(3_600)
            )

            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let midnight = utcCalendar.date(from: DateComponents(
                year: 2027,
                month: 1,
                day: 15
            ))!
            let dailyReset = Int(midnight.timeIntervalSince1970) + 432_000

            var dailyHistory = UsageHistory()
            _ = dailyHistory.record(
                weeklyWindow(usedPercent: 20, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(-120)
            )
            _ = dailyHistory.record(
                weeklyWindow(usedPercent: 20, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(120)
            )
            _ = dailyHistory.record(
                weeklyWindow(usedPercent: 26, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(21_600)
            )
            let dailySixPercent = dailyHistory.usageToday(
                at: midnight.addingTimeInterval(21_600),
                calendar: utcCalendar
            )

            var changedAtMidnightHistory = UsageHistory()
            _ = changedAtMidnightHistory.record(
                weeklyWindow(usedPercent: 20, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(-10)
            )
            _ = changedAtMidnightHistory.record(
                weeklyWindow(usedPercent: 21, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(0.8)
            )
            _ = changedAtMidnightHistory.record(
                weeklyWindow(usedPercent: 26, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(21_600)
            )
            let changedAtMidnight = changedAtMidnightHistory.usageToday(
                at: midnight.addingTimeInterval(21_600),
                calendar: utcCalendar
            )
            let changedAtMidnightPartial = changedAtMidnightHistory.partialUsageToday(
                at: midnight.addingTimeInterval(21_600),
                calendar: utcCalendar
            )

            var earlyLaunchHistory = UsageHistory()
            _ = earlyLaunchHistory.record(
                weeklyWindow(usedPercent: 20, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(240)
            )
            let earlyLaunch = earlyLaunchHistory.usageToday(
                at: midnight.addingTimeInterval(240),
                calendar: utcCalendar
            )
            let earlyLaunchPartial = earlyLaunchHistory.partialUsageToday(
                at: midnight.addingTimeInterval(240),
                calendar: utcCalendar
            )

            var middayLaunchHistory = UsageHistory()
            _ = middayLaunchHistory.record(
                weeklyWindow(usedPercent: 40, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(43_200)
            )
            let middayLaunch = middayLaunchHistory.usageToday(
                at: midnight.addingTimeInterval(43_200),
                calendar: utcCalendar
            )
            let middayLaunchInitialPartial = middayLaunchHistory.partialUsageToday(
                at: midnight.addingTimeInterval(43_200),
                calendar: utcCalendar
            )
            _ = middayLaunchHistory.record(
                weeklyWindow(usedPercent: 43, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(46_800)
            )
            let middayLaunchLaterPartial = middayLaunchHistory.partialUsageToday(
                at: midnight.addingTimeInterval(46_800),
                calendar: utcCalendar
            )

            let resetTime = midnight.addingTimeInterval(21_600)
            let oldReset = Int(resetTime.timeIntervalSince1970)
            let newReset = oldReset + 604_800
            var dailyResetHistory = UsageHistory()
            _ = dailyResetHistory.record(
                weeklyWindow(usedPercent: 90, resetsAt: oldReset),
                at: midnight.addingTimeInterval(60)
            )
            _ = dailyResetHistory.record(
                weeklyWindow(usedPercent: 95, resetsAt: oldReset),
                at: resetTime.addingTimeInterval(-60)
            )
            _ = dailyResetHistory.record(
                weeklyWindow(usedPercent: 1, resetsAt: newReset),
                at: resetTime.addingTimeInterval(60)
            )
            _ = dailyResetHistory.record(
                weeklyWindow(usedPercent: 3, resetsAt: newReset),
                at: resetTime.addingTimeInterval(3_600)
            )
            let dailyAcrossReset = dailyResetHistory.usageToday(
                at: resetTime.addingTimeInterval(3_600),
                calendar: utcCalendar
            )
            let dailyAcrossResetPartial = dailyResetHistory.partialUsageToday(
                at: resetTime.addingTimeInterval(3_600),
                calendar: utcCalendar
            )

            let midnightReset = Int(midnight.timeIntervalSince1970)
            let afterMidnightReset = midnightReset + 604_800
            var midnightResetHistory = UsageHistory()
            _ = midnightResetHistory.record(
                weeklyWindow(usedPercent: 95, resetsAt: midnightReset),
                at: midnight.addingTimeInterval(-60)
            )
            _ = midnightResetHistory.record(
                weeklyWindow(usedPercent: 1, resetsAt: afterMidnightReset),
                at: midnight.addingTimeInterval(60)
            )
            _ = midnightResetHistory.record(
                weeklyWindow(usedPercent: 3, resetsAt: afterMidnightReset),
                at: midnight.addingTimeInterval(3_600)
            )
            let dailyAfterMidnightReset = midnightResetHistory.usageToday(
                at: midnight.addingTimeInterval(3_600),
                calendar: utcCalendar
            )

            var resetGapHistory = UsageHistory()
            _ = resetGapHistory.record(
                weeklyWindow(usedPercent: 90, resetsAt: oldReset),
                at: midnight.addingTimeInterval(60)
            )
            _ = resetGapHistory.record(
                weeklyWindow(usedPercent: 95, resetsAt: oldReset),
                at: resetTime.addingTimeInterval(-3_600)
            )
            _ = resetGapHistory.record(
                weeklyWindow(usedPercent: 2, resetsAt: newReset),
                at: resetTime.addingTimeInterval(3_600)
            )
            let dailyAcrossUnobservedReset = resetGapHistory.usageToday(
                at: resetTime.addingTimeInterval(3_600),
                calendar: utcCalendar
            )
            let dailyAcrossUnobservedResetPartial = resetGapHistory.partialUsageToday(
                at: resetTime.addingTimeInterval(3_600),
                calendar: utcCalendar
            )

            let correctedWindowStart = midnight.addingTimeInterval(28_800)
            let correctedReset = Int(correctedWindowStart.timeIntervalSince1970) + 604_800
            var correctedResetHistory = UsageHistory()
            _ = correctedResetHistory.record(
                weeklyWindow(usedPercent: 4, resetsAt: correctedReset),
                at: midnight.addingTimeInterval(43_200)
            )
            _ = correctedResetHistory.record(
                weeklyWindow(usedPercent: 4, resetsAt: correctedReset + 300),
                at: midnight.addingTimeInterval(43_320)
            )
            let correctedResetPartial = correctedResetHistory.partialUsageToday(
                at: midnight.addingTimeInterval(43_320),
                calendar: utcCalendar
            )

            var unknownResetHistory = UsageHistory()
            _ = unknownResetHistory.record(
                weeklyWindowWithoutReset(usedPercent: 90),
                at: midnight.addingTimeInterval(60)
            )
            _ = unknownResetHistory.record(
                weeklyWindowWithoutReset(usedPercent: 1),
                at: resetTime
            )
            let dailyUnknownReset = unknownResetHistory.usageToday(
                at: resetTime,
                calendar: utcCalendar
            )
            let dailyUnknownResetInitialPartial = unknownResetHistory.partialUsageToday(
                at: resetTime,
                calendar: utcCalendar
            )
            _ = unknownResetHistory.record(
                weeklyWindowWithoutReset(usedPercent: 2),
                at: resetTime.addingTimeInterval(3_600)
            )
            let dailyUnknownResetLaterPartial = unknownResetHistory.partialUsageToday(
                at: resetTime.addingTimeInterval(3_600),
                calendar: utcCalendar
            )

            var losAngelesCalendar = Calendar(identifier: .gregorian)
            losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let springDSTStart = losAngelesCalendar.date(from: DateComponents(
                year: 2026,
                month: 3,
                day: 8
            ))!
            let springDSTEnd = losAngelesCalendar.date(from: DateComponents(
                year: 2026,
                month: 3,
                day: 8,
                hour: 23,
                minute: 30
            ))!
            var springDSTHistory = UsageHistory()
            _ = springDSTHistory.record(
                weeklyWindow(usedPercent: 10),
                at: springDSTStart
            )
            _ = springDSTHistory.record(
                weeklyWindow(usedPercent: 15),
                at: springDSTEnd
            )
            let springDSTUsage = springDSTHistory.usageToday(
                at: springDSTEnd,
                calendar: losAngelesCalendar
            )

            let fallDSTStart = losAngelesCalendar.date(from: DateComponents(
                year: 2026,
                month: 11,
                day: 1
            ))!
            let fallDSTEnd = losAngelesCalendar.date(from: DateComponents(
                year: 2026,
                month: 11,
                day: 1,
                hour: 23,
                minute: 30
            ))!
            var fallDSTHistory = UsageHistory()
            _ = fallDSTHistory.record(
                weeklyWindow(usedPercent: 30),
                at: fallDSTStart
            )
            _ = fallDSTHistory.record(
                weeklyWindow(usedPercent: 37),
                at: fallDSTEnd
            )
            let fallDSTUsage = fallDSTHistory.usageToday(
                at: fallDSTEnd,
                calendar: losAngelesCalendar
            )

            let suiteName = "CodexUsageMenuBarTests.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                fputs("ERROR hourly usage history defaults\n", stderr)
                Foundation.exit(1)
            }
            defaults.removePersistentDomain(forName: suiteName)
            let persistedTracker = UsageTracker(defaults: defaults)
            _ = persistedTracker.record(
                weeklyWindow(usedPercent: 30, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(-60),
                calendar: utcCalendar
            )
            _ = persistedTracker.record(
                weeklyWindow(usedPercent: 30, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(60),
                calendar: utcCalendar
            )
            let reloadedTracker = UsageTracker(defaults: defaults)
            let persistedResult = reloadedTracker.record(
                weeklyWindow(usedPercent: 34, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(3_660),
                calendar: utcCalendar
            )
            defaults.removePersistentDomain(forName: suiteName)
            let partialTracker = UsageTracker(defaults: defaults)
            let partialInitialResult = partialTracker.record(
                weeklyWindow(usedPercent: 40, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(43_200),
                calendar: utcCalendar
            )
            let reloadedPartialTracker = UsageTracker(defaults: defaults)
            let partialLaterResult = reloadedPartialTracker.record(
                weeklyWindow(usedPercent: 43, resetsAt: dailyReset),
                at: midnight.addingTimeInterval(46_800),
                calendar: utcCalendar
            )
            defaults.removePersistentDomain(forName: suiteName)
            guard initial == nil,
                  halfHour == nil,
                  oneHour == 4,
                  ninetyMinutes == 3,
                  afterReset == nil,
                  afterNinetyMinuteGap == nil,
                  atSixtyFiveMinutes == 4,
                  afterSixtyFiveMinutes == nil,
                  resetWithoutTimestamp == nil,
                  persistedResult.hourlyPercent == 4,
                  persistedResult.dailyUsage?.percent == 4,
                  persistedResult.dailyUsage?.isPartial == false,
                  partialInitialResult.dailyUsage?.percent == 0,
                  partialInitialResult.dailyUsage?.isPartial == true,
                  partialLaterResult.dailyUsage?.percent == 3,
                  partialLaterResult.dailyUsage?.isPartial == true,
                  dailySixPercent == 6,
                  changedAtMidnight == nil,
                  changedAtMidnightPartial == 5,
                  earlyLaunch == nil,
                  earlyLaunchPartial == 0,
                  middayLaunch == nil,
                  middayLaunchInitialPartial == 0,
                  middayLaunchLaterPartial == 3,
                  dailyAcrossReset == nil,
                  dailyAcrossResetPartial == 8,
                  dailyAfterMidnightReset == 3,
                  dailyAcrossUnobservedReset == nil,
                  dailyAcrossUnobservedResetPartial == 7,
                  correctedResetPartial == 4,
                  dailyUnknownReset == nil,
                  dailyUnknownResetInitialPartial == 0,
                  dailyUnknownResetLaterPartial == 1,
                  springDSTUsage == 5,
                  fallDSTUsage == 7 else {
                fputs("ERROR usage history\n", stderr)
                Foundation.exit(1)
            }
            print("OK hourly-usage-history")
            print("OK daily-usage-history")
            Foundation.exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
