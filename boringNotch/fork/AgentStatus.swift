//
//  AgentStatus.swift
//  boringNotch
//
//  The single source for how an agent's state looks everywhere: label, color and icon.
//
//    working   blue    pulsing dot           what it's doing ("Running command", "Editing files", …)
//    waiting   yellow  exclamationmark       "Needs input"
//    finished  green   checkmark             "Done"
//

import SwiftUI

extension AgentSession.State {
    var color: Color {
        switch self {
        case .working: return .blue
        case .waiting: return .yellow
        case .finished: return .green
        }
    }
}

extension AgentSession {
    /// Short status shown next to the chat title and in the closed notch.
    var statusLabel: String {
        switch state {
        case .working: return Self.activity(forTool: tool)
        case .waiting: return String(localized: "Needs input")
        case .finished: return String(localized: "Done")
        }
    }

    /// Maps Claude Code and Codex tool names to one set of human-readable activities.
    static func activity(forTool tool: String) -> String {
        if tool.hasPrefix("mcp__") {
            let server = tool.split(separator: "__").dropFirst().first.map(String.init) ?? ""
            return server.isEmpty ? String(localized: "Using a tool") : String(localized: "Using \(server)")
        }
        switch tool {
        case "":
            return String(localized: "Working")
        case "Bash", "BashOutput", "KillShell", "shell", "local_shell", "exec_command", "unified_exec", "write_stdin":
            return String(localized: "Running command")
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch":
            return String(localized: "Editing files")
        case "Read", "view_image", "read_file":
            return String(localized: "Reading files")
        case "Glob", "Grep", "LS", "list_dir", "grep_files":
            return String(localized: "Searching code")
        case "WebFetch", "WebSearch", "web_search", "web_fetch":
            return String(localized: "Browsing the web")
        case "Task", "Agent", "spawn_agent":
            return String(localized: "Running subagent")
        case "TodoWrite", "update_plan":
            return String(localized: "Planning")
        default:
            return String(localized: "Working")
        }
    }
}

/// Compact duration: "1h12m34s", "12m3s", "45s"; zero hours and minutes are left out.
func compactDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let hours = total / 3600
    let minutes = total % 3600 / 60
    let seconds = total % 60
    var result = ""
    if hours > 0 { result += "\(hours)h" }
    if minutes > 0 { result += "\(minutes)m" }
    if seconds > 0 || result.isEmpty { result += "\(seconds)s" }
    return result
}

/// State icon used in rows and in the closed notch.
struct AgentStateIcon: View {
    let state: AgentSession.State

    var body: some View {
        Group {
            switch state {
            case .working:
                AgentWorkingDot(size: 8)
            case .waiting:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(state.color)
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(state.color)
            }
        }
        .frame(width: 14, height: 14)
    }
}

extension AgentSession.Source {
    var bundleIdentifier: String {
        switch self {
        case .claude: return "com.anthropic.claudefordesktop"
        case .codex: return "com.openai.codex"
        }
    }

    /// The desktop app's icon, or nil when the app isn't installed.
    @MainActor var appIcon: NSImage? {
        if let cached = Self.iconCache[self] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        Self.iconCache[self] = icon
        return icon
    }

    @MainActor private static var iconCache: [AgentSession.Source: NSImage?] = [:]
}

/// Small Claude / Codex badge: the app icon, or its initial when the app isn't installed.
struct AgentSourceBadge: View {
    let source: AgentSession.Source
    var size: CGFloat = 12

    var body: some View {
        Group {
            if let icon = source.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Text(source.displayName.prefix(1))
                    .font(.system(size: size * 0.7, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.25).fill(.white.opacity(0.8)))
            }
        }
        .frame(width: size, height: size)
        .help(source.displayName)
    }
}

/// Pulsing dot for "working", also overlaid on the album art while music plays.
struct AgentWorkingDot: View {
    var size: CGFloat = 7
    var outlined = false
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(AgentSession.State.working.color)
            .frame(width: size, height: size)
            .overlay {
                if outlined { Circle().stroke(.black, lineWidth: 1.5) }
            }
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
