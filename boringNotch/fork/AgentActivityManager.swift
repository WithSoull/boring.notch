//
//  AgentActivityManager.swift
//  boringNotch
//
//  Tracks Claude Code / Codex sessions reported by agent-hook.sh through boringnotch://agent URLs.
//

import Combine
import Defaults
import Foundation

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

    let id: String
    let source: Source
    var cwd: String
    var state: State
    var updatedAt: Date

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? source.displayName : name
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
    private let staleWorkingLifetime: TimeInterval = 3 * 60 * 60
    private let amphetamineGracePeriod: Duration = .seconds(120)

    private init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in AgentActivityManager.shared.cleanup() }
        }
    }

    var hasWorkingSessions: Bool {
        sessions.contains { $0.state == .working }
    }

    /// Path of the bundled hook script, for hook configs.
    static var hookScriptPath: String {
        Bundle.main.path(forResource: "agent-hook", ofType: "sh") ?? "/Applications/Boring Notch.app/Contents/Resources/agent-hook.sh"
    }

    func handle(url: URL) {
        guard url.host == "agent",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return }
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        guard let source = AgentSession.Source(rawValue: query["src"] ?? ""),
              let event = query["event"], !event.isEmpty
        else { return }

        let id = "\(source.rawValue)-\(query["session"] ?? "unknown")"
        let cwd = Self.decodeBase64URL(query["cwd"] ?? "") ?? ""
        apply(event: event, id: id, source: source, cwd: cwd)
    }

    private func apply(event: String, id: String, source: AgentSession.Source, cwd: String) {
        let existing = sessions.firstIndex { $0.id == id }

        let newState: AgentSession.State?
        switch event {
        case "UserPromptSubmit", "PostToolUse":
            newState = .working
        case "Stop", "agent-turn-complete":
            newState = .finished
        case "Notification":
            // Idle reminders arrive after Stop; only a running session can be waiting for permission.
            guard let existing, sessions[existing].state != .finished else { return }
            newState = .waiting
        case "SessionEnd":
            if let existing { sessions.remove(at: existing) }
            updateAmphetamine()
            return
        default:
            return
        }

        guard let newState else { return }
        var session = existing.map { sessions[$0] }
            ?? AgentSession(id: id, source: source, cwd: cwd, state: newState, updatedAt: Date())
        if !cwd.isEmpty { session.cwd = cwd }
        session.state = newState
        session.updatedAt = Date()

        if let existing {
            sessions[existing] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }

        if newState != .working {
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
        sessions.removeAll { session in
            let age = now.timeIntervalSince(session.updatedAt)
            return session.state == .finished ? age > finishedLifetime : age > staleWorkingLifetime
        }
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
