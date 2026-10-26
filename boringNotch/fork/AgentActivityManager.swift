//
//  AgentActivityManager.swift
//  boringNotch
//
//  Tracks Claude Code / Codex sessions reported by agent-hook.sh through boringnotch://agent URLs.
//

import AppKit
import Combine
import Defaults

struct AgentSession: Identifiable, Equatable {
    enum Source: String {
        case claude
        case codex

        var displayName: String {
            switch self {
            case .claude: return "Claude"
            case .codex: return "Codex"
            }
        }
    }

    enum State: Equatable {
        case working
        case waiting
        case finished
    }

    /// The agent's own session id (Claude Code session id / Codex thread id).
    let sessionID: String
    let source: Source
    var cwd: String
    var title: String
    /// Last tool the agent used while working, e.g. "Bash".
    var tool: String
    var state: State
    var updatedAt: Date

    var id: String { "\(source.rawValue)-\(sessionID)" }

    /// Short name: the project folder.
    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? source.displayName : name
    }

    var displayTitle: String {
        title.isEmpty ? project : title
    }

    /// Deep link that opens this chat in the agent's desktop app.
    var chatURL: URL? {
        guard sessionID != "unknown" else { return nil }
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        switch source {
        case .claude: return URL(string: "claude://code/continue?session=\(encoded)&source=boringnotch")
        case .codex: return URL(string: "codex://threads/\(encoded)")
        }
    }
}

@MainActor
final class AgentActivityManager: ObservableObject {
    static let shared = AgentActivityManager()

    @Published private(set) var sessions: [AgentSession] = []
    /// Short-lived banner for the closed notch.
    @Published private(set) var banner: AgentSession?

    private var bannerTask: Task<Void, Never>?
    private var amphetamineStopTask: Task<Void, Never>?
    private var cleanupTimer: Timer?

    private let finishedLifetime: TimeInterval = 30 * 60
    /// A working session that sends nothing for this long was most likely interrupted.
    private let staleWorkingTimeout: TimeInterval = 15 * 60
    private let amphetamineGracePeriod: Duration = .seconds(120)

    private init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in AgentActivityManager.shared.cleanup() }
        }
    }

    /// Call at launch: ends an Amphetamine session a previous run started for agents that are gone now.
    func resumeAfterLaunch() {
        updateAmphetamine()
    }

    var hasWorkingSessions: Bool {
        sessions.contains { $0.state == .working }
    }

    func openChat(_ session: AgentSession) {
        if let url = session.chatURL {
            NSWorkspace.shared.open(url)
        }
    }

    func handle(url: URL) {
        guard url.host == "agent",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return }
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        guard let source = AgentSession.Source(rawValue: query["src"] ?? ""),
              let event = query["event"], !event.isEmpty
        else { return }

        apply(
            event: event,
            sessionID: query["session"].flatMap { $0.isEmpty ? nil : $0 } ?? "unknown",
            source: source,
            cwd: Self.decodeBase64URL(query["cwd"] ?? "") ?? "",
            title: Self.decodeBase64URL(query["title"] ?? "") ?? "",
            tool: Self.decodeBase64URL(query["tool"] ?? "") ?? ""
        )
    }

    private func apply(event: String, sessionID: String, source: AgentSession.Source, cwd: String, title: String, tool: String) {
        let id = "\(source.rawValue)-\(sessionID)"
        let existing = sessions.firstIndex { $0.id == id }

        let newState: AgentSession.State
        var showsBanner = false
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            newState = .working
        case "Stop", "agent-turn-complete":
            newState = .finished
            showsBanner = true
        case "Interrupt":
            newState = .finished
        case "Notification", "PermissionRequest":
            // Idle reminders arrive after Stop; only a running session can be waiting for permission.
            guard let existing, sessions[existing].state != .finished else { return }
            newState = .waiting
            showsBanner = true
        case "SessionEnd":
            if let existing { sessions.remove(at: existing) }
            updateAmphetamine()
            return
        default:
            return
        }

        var session = existing.map { sessions[$0] }
            ?? AgentSession(sessionID: sessionID, source: source, cwd: cwd, title: title, tool: "", state: newState, updatedAt: Date())
        if !cwd.isEmpty { session.cwd = cwd }
        if !title.isEmpty { session.title = title }
        if newState == .working {
            if !tool.isEmpty { session.tool = tool }
            if event == "UserPromptSubmit" { session.tool = "" }
        }
        session.state = newState
        session.updatedAt = Date()

        if let existing {
            sessions[existing] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }

        if showsBanner {
            showBanner(session)
        }
        updateAmphetamine()
    }

    private func showBanner(_ session: AgentSession) {
        guard Defaults[.showAgentBanners] else { return }
        bannerTask?.cancel()
        banner = session
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(session.state == .waiting ? 10 : 6))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    func clearFinished() {
        sessions.removeAll { $0.state == .finished }
    }

    private func cleanup() {
        let now = Date()
        for index in sessions.indices
        where sessions[index].state != .finished && now.timeIntervalSince(sessions[index].updatedAt) > staleWorkingTimeout {
            sessions[index].state = .finished
        }
        sessions.removeAll { $0.state == .finished && now.timeIntervalSince($0.updatedAt) > finishedLifetime }
        updateAmphetamine()
    }

    private func updateAmphetamine() {
        guard Defaults[.autoAmphetamineForAgents] else { return }
        let amphetamine = AmphetamineManager.shared
        guard amphetamine.isInstalled else { return }

        if hasWorkingSessions {
            amphetamineStopTask?.cancel()
            amphetamineStopTask = nil
            if !amphetamine.isActive {
                amphetamine.start(forAgents: true)
            }
        } else if amphetamine.startedForAgents, amphetamineStopTask == nil {
            amphetamineStopTask = Task { [weak self] in
                try? await Task.sleep(for: self?.amphetamineGracePeriod ?? .seconds(120))
                guard let self, !Task.isCancelled else { return }
                self.amphetamineStopTask = nil
                if !self.hasWorkingSessions && AmphetamineManager.shared.startedForAgents {
                    AmphetamineManager.shared.stop()
                }
            }
        }
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
    }
}
