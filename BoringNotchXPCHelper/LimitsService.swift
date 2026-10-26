//
//  LimitsService.swift
//  BoringNotchXPCHelper
//
//  Subscription limits through the agents' own CLIs, never their tokens:
//  Claude Code's `/usage` command (no model call) and Codex's local `codex app-server` JSON-RPC.
//  Each Codex account is a separate CODEX_HOME folder.
//

import Foundation

extension BoringNotchXPCHelper {
    private static let limitsQueue = DispatchQueue(label: "boringNotch.limits", attributes: .concurrent)

    // MARK: Claude

    @objc func claudeUsage(with reply: @escaping (Data?) -> Void) {
        Self.limitsQueue.async {
            guard let claude = Self.findExecutable("claude") else {
                reply(Self.json(["error": "notInstalled"]))
                return
            }
            let result = Self.run(
                claude,
                arguments: ["-p", "/usage", "--no-session-persistence", "--settings", #"{"disableAllHooks":true}"#, "--strict-mcp-config"],
                environment: [:],
                timeout: 45
            )
            guard let output = result else {
                reply(Self.json(["error": "failed"]))
                return
            }
            reply(Self.json(Self.parseClaudeUsage(output)))
        }
    }

    /// Parses "Current session: 80% used · resets Oct 27 at 2:10am (Europe/Moscow)" and the "Current week (all models)" line.
    static func parseClaudeUsage(_ text: String, now: Date = Date()) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, label) in [("fiveHour", #"Current session"#), ("week", #"Current week \(all models\)"#)] {
            let pattern = label + #":\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+(.+?)\s*\(([^)]+)\))?"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let usedRange = Range(match.range(at: 1), in: text),
                  let used = Double(text[usedRange])
            else { continue }
            var window: [String: Any] = ["used": used]
            if let dateRange = Range(match.range(at: 2), in: text), let zoneRange = Range(match.range(at: 3), in: text),
               let resets = parseResetDate(String(text[dateRange]), timeZone: TimeZone(identifier: String(text[zoneRange])), now: now) {
                window["resetsAt"] = resets.timeIntervalSince1970
            }
            result[key] = window
        }
        if result.isEmpty {
            result["error"] = text.localizedCaseInsensitiveContains("log in") || text.localizedCaseInsensitiveContains("login")
                ? "notLoggedIn" : "parseFailed"
        }
        return result
    }

    private static func parseResetDate(_ text: String, timeZone: TimeZone?, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone

        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, yyyy 'at' h:mma", "MMM d, yyyy 'at' ha"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: text) else { continue }
            if format.contains("yyyy") { return parsed }
            // No year in the text: take the one that puts the reset closest after now.
            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            parts.year = calendar.component(.year, from: now)
            guard var date = calendar.date(from: parts) else { return nil }
            if date < now.addingTimeInterval(-86400), let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
            return date
        }
        for format in ["h:mma", "ha"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: text) else { continue }
            let time = calendar.dateComponents([.hour, .minute], from: parsed)
            guard var date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now) else { return nil }
            if date < now, let next = calendar.date(byAdding: .day, value: 1, to: date) { date = next }
            return date
        }
        return nil
    }

    // MARK: Codex

    /// Reads the account and its rate limits from the account stored in `home` (a CODEX_HOME folder).
    @objc func codexLimits(_ home: String, with reply: @escaping (Data?) -> Void) {
        Self.limitsQueue.async {
            guard let server = CodexAppServer(home: Self.expand(home)) else {
                reply(Self.json(["error": "notInstalled"]))
                return
            }
            defer { server.stop() }
            guard server.initialize() else {
                reply(Self.json(["error": "failed"]))
                return
            }
            let account = server.request("account/read", params: ["refreshToken": false])
            guard let accountResult = account?["result"] as? [String: Any] else {
                reply(Self.json(["error": "failed"]))
                return
            }
            guard accountResult["account"] is [String: Any] else {
                reply(Self.json(["error": "notLoggedIn"]))
                return
            }
            let limits = server.request("account/rateLimits/read", params: nil)
            var payload: [String: Any] = ["account": accountResult["account"] as Any]
            if let result = limits?["result"] { payload["limits"] = result } else { payload["error"] = "failed" }
            reply(Self.json(payload))
        }
    }

    /// Signs `home` into a ChatGPT account: opens the official login page and waits for it to finish (up to 10 minutes).
    @objc func codexLogin(_ home: String, with reply: @escaping (Bool) -> Void) {
        Self.limitsQueue.async {
            let path = Self.expand(home)
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            guard let server = CodexAppServer(home: path) else {
                reply(false)
                return
            }
            defer { server.stop() }
            guard server.initialize(),
                  let response = server.request("account/login/start", params: ["type": "chatgpt"]),
                  let result = response["result"] as? [String: Any],
                  let authURL = result["authUrl"] as? String
            else {
                reply(false)
                return
            }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [authURL]
            try? open.run()
            let completed = server.waitForNotification("account/login/completed", timeout: 600)
            reply((completed?["params"] as? [String: Any])?["success"] as? Bool ?? false)
        }
    }

    // MARK: Helpers

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func json(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    /// The helper has a minimal PATH; look where installers put these CLIs.
    static func findExecutable(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin"]
            .map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func childEnvironment(_ extra: [String: String]) -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LANG"] = "en_US.UTF-8"
        environment.merge(extra) { _, new in new }
        return environment
    }

    /// Runs a command to completion and returns its stdout; nil on launch failure, non-zero exit or timeout.
    static func run(_ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = childEnvironment(environment)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Minimal line-delimited JSON-RPC client for one short-lived `codex app-server` process.
private final class CodexAppServer {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSCondition()
    private var buffer = Data()
    private var messages: [[String: Any]] = []
    private var nextID = 1

    init?(home: String) {
        guard let codex = BoringNotchXPCHelper.findExecutable("codex") else { return nil }
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["app-server"]
        process.environment = BoringNotchXPCHelper.childEnvironment(["CODEX_HOME": home])
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.receive(handle.availableData)
        }
        do { try process.run() } catch { return nil }
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    func initialize() -> Bool {
        guard request("initialize", params: ["clientInfo": ["name": "boringnotch", "version": "1"]])?["result"] != nil else { return false }
        send(["jsonrpc": "2.0", "method": "initialized"])
        return true
    }

    func request(_ method: String, params: Any?, timeout: TimeInterval = 20) -> [String: Any]? {
        let id = nextID
        nextID += 1
        send(["jsonrpc": "2.0", "id": id, "method": method, "params": params ?? NSNull()])
        return wait(timeout: timeout) { ($0["id"] as? Int) == id }
    }

    func waitForNotification(_ method: String, timeout: TimeInterval) -> [String: Any]? {
        wait(timeout: timeout) { ($0["method"] as? String) == method && $0["id"] == nil }
    }

    private func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if data.isEmpty { lock.broadcast(); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                messages.append(object)
            }
        }
        lock.broadcast()
    }

    private func wait(timeout: TimeInterval, matching: ([String: Any]) -> Bool) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        defer { lock.unlock() }
        while true {
            if let index = messages.firstIndex(where: matching) {
                return messages.remove(at: index)
            }
            guard process.isRunning, lock.wait(until: deadline) else { return nil }
        }
    }
}
