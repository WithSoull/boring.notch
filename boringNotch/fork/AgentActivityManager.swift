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
    /// Claude desktop app's own session id ("local_…"); its deep links don't accept the CLI session id.
    var chatID: String
    var cwd: String
    var title: String
    /// Last tool the agent used while working, e.g. "Bash".
    var tool: String
    var state: State
    /// When the current state began (a new prompt also restarts "working"); drives the duration shown.
    var stateSince: Date
    /// Last event of any kind, including heartbeats.
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
        let id = chatID.isEmpty ? sessionID : chatID
        guard id != "unknown" else { return nil }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
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
    private var autoAmphetamineObserver: AnyCancellable?

    private let finishedLifetime: TimeInterval = 30 * 60
    /// A working session that sends nothing for this long was most likely interrupted.
    private let staleWorkingTimeout: TimeInterval = 15 * 60
    private let amphetamineGracePeriod: Duration = .seconds(120)

    private init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in AgentActivityManager.shared.cleanup() }
        }
        autoAmphetamineObserver = Defaults.publisher(.autoAmphetamineForAgents, options: [])
            .receive(on: DispatchQueue.main)
            .sink { _ in Task { @MainActor in AgentActivityManager.shared.updateAmphetamine() } }
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
            tool: Self.decodeBase64URL(query["tool"] ?? "") ?? "",
            chatID: query["chat"] ?? "",
            notificationType: query["ntype"] ?? ""
        )
    }

    private func apply(
        event: String, sessionID: String, source: AgentSession.Source, cwd: String, title: String, tool: String,
        chatID: String, notificationType: String
    ) {
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
        case "PermissionRequest":
            // An explicit request: also creates the session if the app didn't see it start (e.g. after a relaunch).
            newState = .waiting
            showsBanner = true
        case "Notification":
            // Claude's permission prompts are explicit too; idle reminders arrive after Stop and only update running sessions.
            if notificationType != "permission_prompt" {
                guard let existing, sessions[existing].state != .finished else { return }
            }
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
            ?? AgentSession(
                sessionID: sessionID, source: source, chatID: chatID, cwd: cwd, title: title, tool: "",
                state: newState, stateSince: Date(), updatedAt: Date()
            )
        if !chatID.isEmpty { session.chatID = chatID }
        if !cwd.isEmpty { session.cwd = cwd }
        if !title.isEmpty { session.title = title }
        if newState == .working {
            if !tool.isEmpty { session.tool = tool }
            if event == "UserPromptSubmit" { session.tool = "" }
        }
        if session.state != newState || event == "UserPromptSubmit" {
            session.stateSince = Date()
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
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    func clearFinished() {
        sessions.removeAll { $0.state == .finished }
    }

    private func cleanup() {
        let now = Date()
        // Only working sessions send heartbeats; a session waiting for the user stays waiting.
        for index in sessions.indices
        where sessions[index].state == .working && now.timeIntervalSince(sessions[index].updatedAt) > staleWorkingTimeout {
            sessions[index].state = .finished
            sessions[index].stateSince = now
        }
        sessions.removeAll { $0.state == .finished && now.timeIntervalSince($0.updatedAt) > finishedLifetime }
        updateAmphetamine()
    }

    private func updateAmphetamine() {
        let amphetamine = AmphetamineManager.shared
        guard amphetamine.isInstalled else { return }

        guard Defaults[.autoAmphetamineForAgents] else {
            // Turning the automation off ends the session it started; a manual session is left alone.
            amphetamineStopTask?.cancel()
            amphetamineStopTask = nil
            if amphetamine.startedForAgents && amphetamine.isActive { amphetamine.stop() }
            return
        }

        if hasWorkingSessions {
            amphetamineStopTask?.cancel()
            amphetamineStopTask = nil
            if !amphetamine.isActive && !amphetamine.isStarting {
                amphetamine.start(forAgents: true)
            }
        } else if amphetamine.startedForAgents, amphetamineStopTask == nil {
            amphetamineStopTask = Task { [weak self] in
                try? await Task.sleep(for: self?.amphetamineGracePeriod ?? .seconds(120))
                guard let self, !Task.isCancelled else { return }
                self.amphetamineStopTask = nil
                if Defaults[.autoAmphetamineForAgents] && !self.hasWorkingSessions && AmphetamineManager.shared.startedForAgents {
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
