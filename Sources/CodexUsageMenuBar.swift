import AppKit
import Foundation
import ServiceManagement

private enum AppError: LocalizedError {
    case codexNotFound
    case serverStopped
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex CLIが見つかりません。ChatGPT/Codexアプリをインストールしてください。"
        case .serverStopped:
            return "Codex App Serverとの接続が終了しました。"
        case .invalidResponse:
            return "Codexから不正な応答を受け取りました。"
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
        alert.messageText = "Applicationsフォルダへ移動しますか？"
        let replacement = FileManager.default.fileExists(atPath: destinationURL.path)
            ? "既存のCodex Usageを置き換え、"
            : ""
        alert.informativeText = "\(replacement)Codex UsageをApplicationsフォルダへ移動して開きます。"
        alert.addButton(withTitle: "移動して開く")
        alert.addButton(withTitle: "このまま開く")

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
            failure.messageText = "Applicationsフォルダへ移動できませんでした"
            failure.informativeText = "この場所から起動を続けます。\n\n\(error.localizedDescription)"
            failure.addButton(withTitle: "OK")
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
                userInfo: [NSLocalizedDescriptionKey: "インストール後のアプリを開けませんでした。"]
            )
        }
    }
}

private struct LimitWindow {
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
}

private struct UsageSnapshot {
    let primary: LimitWindow?
    let secondary: LimitWindow?
    let planType: String?
    let updatedAt: Date

    init(result: [String: Any]) throws {
        guard let rateLimits = result["rateLimits"] as? [String: Any] else {
            throw AppError.invalidResponse
        }
        primary = LimitWindow(json: rateLimits["primary"] as? [String: Any])
        secondary = LimitWindow(json: rateLimits["secondary"] as? [String: Any])
        planType = rateLimits["planType"] as? String
        updatedAt = Date()
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
                        "name": "codex-usage-menubar",
                        "title": "Codex Usage Menu Bar",
                        "version": "1.1.0"
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
                let message = errorObject["message"] as? String ?? "Codex App Serverエラー"
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
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var snapshot: UsageSnapshot?
    private var errorMessage: String?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ApplicationRelocator.offerMoveAndRelaunch() {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Codex Usage")
        statusItem.button?.imagePosition = .imageLeading
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
        let primary = snapshot.primary.map { "5h \($0.remainingPercent)%" } ?? "5h —"
        let secondary = snapshot.secondary.map { "W \($0.remainingPercent)%" } ?? "W —"
        statusItem.button?.title = "\(primary)  \(secondary)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Codex Usage", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        if let snapshot {
            addWindow(snapshot.primary, fallbackName: "5時間枠", to: menu)
            menu.addItem(.separator())
            addWindow(snapshot.secondary, fallbackName: "週次枠", to: menu)
            menu.addItem(.separator())
            if let plan = snapshot.planType {
                addDisabled("プラン: \(formatPlan(plan))", to: menu)
            }
            addDisabled("最終更新: \(timeFormatter.string(from: snapshot.updatedAt))", to: menu)
        } else {
            addDisabled(isRefreshing ? "Usageを取得中…" : "Usageを取得できません", to: menu)
        }

        if let errorMessage {
            menu.addItem(.separator())
            let errorItem = NSMenuItem(title: "エラー: \(errorMessage)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "今すぐ更新", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing
        menu.addItem(refreshItem)

        if #available(macOS 13.0, *) {
            let launchItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
            launchItem.target = self
            launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(launchItem)
        }

        let openItem = NSMenuItem(title: "ChatGPTを開く", action: #selector(openChatGPT), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
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
            name = "5時間枠"
        } else if let minutes = window.durationMinutes, minutes == 10_080 {
            name = "週次枠"
        } else {
            name = fallbackName
        }
        addDisabled("\(name): 残り \(window.remainingPercent)%（使用 \(window.usedPercent)%）", to: menu)
        if let reset = window.resetsAt {
            addDisabled("リセット: \(resetFormatter.string(from: reset))", indent: 1, to: menu)
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
            showAlert(title: "自動起動を変更できません", message: "アプリをApplicationsフォルダへ移動してから、もう一度お試しください。\n\n\(error.localizedDescription)")
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
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private lazy var resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

@main
private enum CodexUsageMenuBarApp {
    static func main() {
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
                    let primary = snapshot.primary?.remainingPercent.description ?? "—"
                    let secondary = snapshot.secondary?.remainingPercent.description ?? "—"
                    print("OK 5h_remaining=\(primary)% weekly_remaining=\(secondary)%")
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

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
