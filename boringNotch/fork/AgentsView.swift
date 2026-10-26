//
//  AgentsView.swift
//  boringNotch
//
//  Notch tab: agent sessions, system load and Amphetamine controls.
//

import Defaults
import SwiftUI

struct AgentsView: View {
    @ObservedObject private var agents = AgentActivityManager.shared
    @ObservedObject private var stats = SystemStatsMonitor.shared
    @ObservedObject private var amphetamine = AmphetamineManager.shared
    @ObservedObject private var devServers = DevServersManager.shared
    @Default(.autoAmphetamineForAgents) private var autoAmphetamine

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sessionList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 10) {
                statsSection
                if amphetamine.isInstalled {
                    amphetamineSection
                }
            }
            .frame(width: 190, alignment: .topLeading)
        }
        .padding(.top, 6)
        .onAppear {
            stats.startWatching()
            devServers.startWatching()
            amphetamine.refresh()
        }
        .onDisappear {
            stats.stopWatching()
            devServers.stopWatching()
        }
    }

    // MARK: Sessions and servers

    @ViewBuilder
    private var sessionList: some View {
        if agents.sessions.isEmpty && devServers.servers.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.title2)
                Text("No agent sessions")
                Text("Install hooks in Settings → Agents")
                    .font(.caption)
            }
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agents.sessions) { session in
                        AgentSessionRow(session: session)
                    }

                    if !devServers.servers.isEmpty {
                        Text("Servers")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.gray)
                            .padding(.top, agents.sessions.isEmpty ? 0 : 4)
                        ForEach(devServers.servers) { server in
                            DevServerRow(server: server)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatBar(label: "CPU", value: stats.cpuUsage, detail: "\(Int(stats.cpuUsage * 100))%")
            StatBar(
                label: "RAM",
                value: stats.memoryFraction,
                detail: String(format: "%.1f / %.0f GB", Double(stats.memoryUsed) / 1_073_741_824, Double(stats.memoryTotal) / 1_073_741_824)
            )
        }
    }

    // MARK: Amphetamine

    private var amphetamineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: amphetamine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(amphetamine.isActive ? .orange : .gray)
                Text(amphetamineStatus)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))

            HStack(spacing: 6) {
                if amphetamine.isActive {
                    pill("Stop") { amphetamine.stop() }
                } else {
                    pill("∞") { amphetamine.start() }
                    pill("1h") { amphetamine.start(minutes: 60) }
                    pill("3h") { amphetamine.start(minutes: 180) }
                }
            }

            Button {
                autoAmphetamine.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Auto while agents work")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    // Custom switch: system switches render grey in the never-key notch window.
                    Capsule()
                        .fill(autoAmphetamine ? Color.green : Color.white.opacity(0.15))
                        .frame(width: 28, height: 16)
                        .overlay(alignment: autoAmphetamine ? .trailing : .leading) {
                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .padding(2)
                        }
                        .animation(.smooth(duration: 0.2), value: autoAmphetamine)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var amphetamineStatus: String {
        guard amphetamine.isActive else { return String(localized: "Mac can sleep") }
        if amphetamine.startedForAgents { return String(localized: "Awake for agents") }
        if amphetamine.timeRemaining > 0 {
            return String(localized: "Awake · \(compactDuration(TimeInterval(amphetamine.timeRemaining))) left")
        }
        return String(localized: "Awake")
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    @State private var hovering = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            AgentStateIcon(state: session.state)
            AgentSourceBadge(source: session.source, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                (Text(session.displayTitle).foregroundStyle(.white)
                    + Text(" — \(session.statusLabel)").foregroundStyle(session.state.color))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(session.project)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let errorMessage {
                RowErrorText(message: errorMessage)
            } else if hovering && !session.cwd.isEmpty {
                Button {
                    Task {
                        let opened = await XPCHelperClient.shared.openFolder(path: session.cwd, withApplication: Defaults[.agentFolderApp])
                        if !opened { await showError(String(localized: "Couldn't open folder")) }
                    }
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Open \(session.cwd)")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(compactDuration(context.date.timeIntervalSince(session.stateSince)))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if !AgentActivityManager.shared.openChat(session) {
                Task { await showError(String(localized: "No chat link")) }
            }
        }
        .help("Open chat in \(session.source.displayName)")
    }

    @MainActor private func showError(_ message: String) async {
        errorMessage = message
        try? await Task.sleep(for: .seconds(3))
        if errorMessage == message { errorMessage = nil }
    }
}

/// Short red message shown in place of a row's trailing content after a failed action.
private struct RowErrorText: View {
    let message: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.caption2)
        .foregroundStyle(.red)
        .lineLimit(1)
        .transition(.opacity)
    }
}

private struct StatBar: View {
    let label: String
    let value: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.white)
                Spacer()
                Text(detail).foregroundStyle(.gray).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 5)
        }
    }

    private var color: Color {
        value > 0.85 ? .red : value > 0.6 ? .orange : .green
    }
}

/// Closed-notch banner: an agent finished or needs input. Layout: icon + project | status.
struct AgentBannerActivity: View {
    let session: AgentSession

    var body: some View {
        ClosedNotchSidesView {
            AgentStateIcon(state: session.state)
            Text(session.project)
                .truncationMode(.tail)
        } trailing: {
            Text(session.statusLabel)
                .foregroundStyle(session.state.color)
            AgentSourceBadge(source: session.source, size: 18)
        }
    }
}

/// Closed-notch activity while agents are working (shown when no music is playing). Same layout as the banner.
struct WorkingAgentsActivity: View {
    let sessions: [AgentSession]

    var body: some View {
        ClosedNotchSidesView {
            AgentStateIcon(state: .working)
            Text(sessions.first?.project ?? "")
                .truncationMode(.tail)
        } trailing: {
            Text(label)
                .foregroundStyle(AgentSession.State.working.color)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.4), value: label)
            ForEach(sources, id: \.self) { AgentSourceBadge(source: $0, size: 18) }
        }
    }

    private var label: String {
        sessions.count > 1 ? String(localized: "\(sessions.count) working") : sessions.first?.statusLabel ?? ""
    }

    /// Distinct agents among the working sessions, most recent first.
    private var sources: [AgentSession.Source] {
        sessions.reduce(into: []) { result, session in
            if !result.contains(session.source) { result.append(session.source) }
        }
    }
}

struct DevServerRow: View {
    let server: DevServer
    @State private var hovering = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(":\(server.port)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(server.project)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(server.name)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let errorMessage {
                RowErrorText(message: errorMessage)
            } else if hovering {
                Button {
                    Task {
                        guard !(await DevServersManager.shared.stop(server)) else { return }
                        let message = String(localized: "Couldn't stop")
                        errorMessage = message
                        try? await Task.sleep(for: .seconds(3))
                        if errorMessage == message { errorMessage = nil }
                    }
                } label: {
                    Image(systemName: "stop.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Stop process \(server.pid)")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { DevServersManager.shared.open(server) }
        .help("Open http://localhost:\(server.port) · \(server.cwd)")
    }
}
