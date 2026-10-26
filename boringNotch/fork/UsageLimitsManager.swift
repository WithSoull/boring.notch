//
//  UsageLimitsManager.swift
//  boringNotch
//
//  Subscription limits of Claude (from its statusLine bridge) and every configured Codex account (through the XPC helper).
//  Refreshed every few minutes in the background (for warnings) and more often while the Agents tab is open.
//

import Combine
import Defaults
import Foundation

struct UsageWindow: Equatable {
    var usedPercent: Double
    var resetsAt: Date?

    var remainingPercent: Int { Int((100 - usedPercent).rounded().clamped(to: 0...100)) }
    /// Past its reset time the numbers are from the previous window.
    var isStale: Bool { resetsAt.map { $0 < Date() } ?? false }
}

struct UsageLimits: Identifiable, Equatable {
    enum Source: Equatable {
        case claude
        case codex(CodexAccount)
    }

    let id: String
    let source: Source
    var title: String
    var fiveHour: UsageWindow?
    var week: UsageWindow?
    /// Codex free full resets still available, and when the first of them expires.
    var resetCredits = 0
    var nextCreditExpiry: Date?
    var updatedAt: Date?
    var error: String?

    var agent: AgentSession.Source {
        if case .claude = source { return .claude }
        return .codex
    }

    var errorText: String? {
        switch error {
        case nil: return nil
        case "notInstalled": return String(localized: "CLI not found")
        case "notLoggedIn": return String(localized: "Not signed in")
        case "noStatusLine": return String(localized: "No data yet: install the statusLine in Settings")
        default: return String(localized: "Couldn't read limits")
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

@MainActor
final class UsageLimitsManager: ObservableObject {
    static let shared = UsageLimitsManager()

    /// Claude first, then Codex accounts in settings order.
    @Published private(set) var limits: [UsageLimits] = []
    /// Short-lived closed-notch warning.
    @Published private(set) var warning: UsageLimits?

    static let warningThreshold = 15

    private let backgroundInterval: TimeInterval = 5 * 60
    private let watchingInterval: TimeInterval = 60
    private var timer: Timer?
    private var watchers = 0
    private var refreshing = false
    private var lastRefresh: Date?
    private var warningTask: Task<Void, Never>?
    /// Last warning level shown per account and 5-hour window, so each threshold warns once.
    private var warned: [String: (resetsAt: Date?, level: Int)] = [:]
    private var settingsObserver: AnyCancellable?
    private var claudeWatcher: DispatchSourceFileSystemObject?

    private init() {}

    func start() {
        guard timer == nil else { return }
        settingsObserver = Defaults.publisher(keys: .codexAccounts, .showUsageLimits, options: [])
            .receive(on: DispatchQueue.main)
            .sink { _ in Task { @MainActor in UsageLimitsManager.shared.refresh(force: true) } }
        watchClaudeFile()
        refresh(force: true)
        schedule()
    }

    func startWatching() {
        watchers += 1
        refresh(force: false)
        schedule()
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        let interval = watchers > 0 ? watchingInterval : backgroundInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in UsageLimitsManager.shared.refresh(force: true) }
        }
    }

    /// `force: false` skips the read if the last one was under a minute ago.
    func refresh(force: Bool) {
        guard Defaults[.showUsageLimits] else {
            limits = []
            return
        }
        guard !refreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < watchingInterval { return }
        refreshing = true
        lastRefresh = Date()
        let accounts = Defaults[.codexAccounts]
        Task {
            let claude = Self.readClaude()
            var codex: [UsageLimits] = []
            for account in accounts {
                codex.append(await Self.readCodex(account, previous: limits.first { $0.id == "codex-\(account.id)" }))
            }
            let updated = [claude] + codex
            if updated != limits { limits = updated }
            refreshing = false
            checkWarnings()
        }
    }

    func login(_ account: CodexAccount) async -> Bool {
        let succeeded = await XPCHelperClient.shared.codexLogin(home: account.home)
        refresh(force: true)
        return succeeded
    }

    // MARK: Reading

    /// Written by fork/claude-statusline.sh into this app's container after every Claude Code response.
    static var claudeLimitsFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("claude-limits.json")
    }

    private static func readClaude() -> UsageLimits {
        var result = UsageLimits(id: "claude", source: .claude, title: "Claude")
        guard let data = try? Data(contentsOf: claudeLimitsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            result.error = "noStatusLine"
            return result
        }
        result.fiveHour = window(json["fiveHour"], used: "used", resets: "resetsAt")
        result.week = window(json["week"], used: "used", resets: "resetsAt")
        result.updatedAt = (json["updatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return result
    }

    /// Re-reads Claude's numbers as soon as the statusLine bridge rewrites the file.
    private func watchClaudeFile() {
        let directory = Self.claudeLimitsFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { UsageLimitsManager.shared.reloadClaude() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        claudeWatcher = source
    }

    private func reloadClaude() {
        guard Defaults[.showUsageLimits] else { return }
        let claude = Self.readClaude()
        guard let index = limits.firstIndex(where: { $0.id == "claude" }), limits[index] != claude else { return }
        limits[index] = claude
        checkWarnings()
    }

    private static func readCodex(_ account: CodexAccount, previous: UsageLimits?) async -> UsageLimits {
        var result = UsageLimits(id: "codex-\(account.id)", source: .codex(account), title: account.name.isEmpty ? "Codex" : account.name)
        guard let data = await XPCHelperClient.shared.codexLimits(home: account.home),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return keepingPrevious(previous, into: result, error: "failed")
        }
        if let accountInfo = json["account"] as? [String: Any], account.name.isEmpty, let email = accountInfo["email"] as? String {
            result.title = email
        }
        if let error = json["error"] as? String, json["limits"] == nil {
            return keepingPrevious(previous, into: result, error: error)
        }
        guard let response = json["limits"] as? [String: Any] else {
            return keepingPrevious(previous, into: result, error: "failed")
        }
        // Prefer the "codex" group; other groups (per-model limits) aren't summed in.
        let groups = response["rateLimitsByLimitId"] as? [String: Any]
        let snapshot = (groups?["codex"] ?? response["rateLimits"]) as? [String: Any]
        for key in ["primary", "secondary"] {
            guard let raw = snapshot?[key] as? [String: Any],
                  let parsed = window(raw, used: "usedPercent", resets: "resetsAt")
            else { continue }
            // Window lengths come from the response; don't assume primary is 5 hours.
            let minutes = raw["windowDurationMins"] as? Int ?? (key == "primary" ? 300 : 10080)
            if minutes <= 24 * 60 { result.fiveHour = parsed } else { result.week = parsed }
        }
        if let credits = response["rateLimitResetCredits"] as? [String: Any] {
            let available = (credits["credits"] as? [[String: Any]] ?? []).filter { ($0["status"] as? String) == "available" }
            result.resetCredits = credits["availableCount"] as? Int ?? available.count
            result.nextCreditExpiry = available.compactMap { ($0["expiresAt"] as? Double).map(Date.init(timeIntervalSince1970:)) }.min()
        }
        result.updatedAt = Date()
        return result
    }

    private static func window(_ raw: Any?, used: String, resets: String) -> UsageWindow? {
        guard let raw = raw as? [String: Any], let value = (raw[used] as? NSNumber)?.doubleValue else { return nil }
        let resetsAt = (raw[resets] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return UsageWindow(usedPercent: value, resetsAt: resetsAt)
    }

    /// A failed read keeps the last numbers (marked with the error) rather than showing them as gone.
    private static func keepingPrevious(_ previous: UsageLimits?, into result: UsageLimits, error: String) -> UsageLimits {
        var result = previous ?? result
        result.error = error
        return result
    }

    // MARK: Warnings

    private func checkWarnings() {
        guard Defaults[.usageLimitWarnings] else { return }
        for item in limits where item.error == nil {
            guard let window = item.fiveHour, !window.isStale else { continue }
            let remaining = window.remainingPercent
            let level = remaining <= 0 ? 2 : remaining <= Self.warningThreshold ? 1 : 0
            let previous = warned[item.id]
            let sameWindow = previous?.resetsAt == window.resetsAt
            if level > 0 && (!sameWindow || level > (previous?.level ?? 0)) {
                showWarning(item)
            }
            if !sameWindow || level > (previous?.level ?? 0) {
                warned[item.id] = (window.resetsAt, level)
            }
        }
    }

    private func showWarning(_ item: UsageLimits) {
        warningTask?.cancel()
        warning = item
        warningTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            warning = nil
        }
    }
}
