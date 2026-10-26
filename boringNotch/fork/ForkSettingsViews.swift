//
//  ForkSettingsViews.swift
//  boringNotch
//
//  Settings pages for fork-only features.
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct SnippetsSettings: View {
    @Default(.snippets) private var snippets

    var body: some View {
        Form {
            Section {
                ForEach($snippets) { $snippet in
                    HStack(alignment: .top) {
                        VStack(spacing: 6) {
                            TextField("Title", text: $snippet.title)
                            TextField("Text to copy", text: $snippet.value, axis: .vertical)
                                .lineLimit(1...4)
                        }
                        Button(role: .destructive) {
                            snippets.removeAll { $0.id == snippet.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { snippets.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    snippets.append(Snippet(title: "", value: ""))
                } label: {
                    Label("Add snippet", systemImage: "plus")
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Shown in the Snippets tab of the notch. Click a snippet there to copy its text.")
            }

            Section {
                KeyboardShortcuts.Recorder("Open Snippets tab:", name: .openSnippets)
            } header: {
                Text("Shortcut")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Snippets")
    }
}

/// Where the hook commands expect the app; the hooks call the script inside this bundle.
private let installedAppPath = "/Applications/Boring Notch.app"

struct AgentsAndStatusSettings: View {
    @ObservedObject private var amphetamine = AmphetamineManager.shared
    @Default(.vpnServiceName) private var vpnServiceName
    @Default(.agentFolderApp) private var agentFolderApp
    @State private var copiedClaude = false
    @State private var copiedCodex = false

    private let hookPath = installedAppPath + "/Contents/Resources/agent-hook.sh"

    var body: some View {
        Form {
            DeviceControlsSettings()
            Section {
                Defaults.Toggle(key: .showVPNStatus) {
                    Text("Show VPN status in the notch header")
                }
                TextField("VPN connection name", text: $vpnServiceName)
            } header: {
                Text("VPN")
            } footer: {
                Text("Name of the VPN as listed in System Settings → VPN (run `scutil --nc list` to see it). Click the indicator to connect or disconnect.")
            }

            Section {
                if amphetamine.isInstalled {
                    Defaults.Toggle(key: .showAmphetamineButton) {
                        Text("Show Amphetamine button in the notch header")
                    }
                    Defaults.Toggle(key: .autoAmphetamineForAgents) {
                        Text("Keep Mac awake while agents are working")
                    }
                } else {
                    Text("Amphetamine is not installed.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Amphetamine")
            } footer: {
                Text("Closed-lid mode is configured in Amphetamine itself (Amphetamine Enhancer → Closed-Display Mode).")
            }

            Section {
                Defaults.Toggle(key: .showAgentBanners) {
                    Text("Show a banner when an agent finishes or needs input")
                }
                Defaults.Toggle(key: .showWorkingAgentsIndicator) {
                    Text("Show working agents in the closed notch")
                }
                TextField("Open agent folders in", text: $agentFolderApp, prompt: Text("Finder"))
                HStack {
                    Text("Claude Code hooks (merge into ~/.claude/settings.json)")
                    Spacer()
                    Button(copiedClaude ? "Copied" : "Copy") {
                        copy(claudeHooks)
                        copiedClaude = true
                    }
                }
                HStack {
                    Text("Codex hooks (save as ~/.codex/hooks.json, then approve them in Codex)")
                    Spacer()
                    Button(copiedCodex ? "Copied" : "Copy") {
                        copy(codexHooks)
                        copiedCodex = true
                    }
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Hooks call the script bundled with this app, which reports events back via boringnotch:// links. Click a session in the Agents tab to open its chat.")
            }

            AgentHooksDiagnostics()
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Agents & Status")
    }

    private var claudeHooks: String {
        hooksJSON(source: "claude", events: ["UserPromptSubmit", "Stop", "Notification", "SessionEnd"], toolEvents: ["PreToolUse", "PostToolUse"])
    }

    private var codexHooks: String {
        hooksJSON(
            source: "codex",
            events: ["UserPromptSubmit", "Stop", "Interrupt", "SessionEnd"],
            toolEvents: ["PermissionRequest", "PreToolUse", "PostToolUse"]
        )
    }

    private func hooksJSON(source: String, events: [String], toolEvents: [String]) -> String {
        let command = "/bin/sh '\(hookPath)' \(source)"
        let entry = #"[{"hooks":[{"type":"command","command":"\#(command)"}]}]"#
        let toolEntry = #"[{"matcher":"*","hooks":[{"type":"command","command":"\#(command)"}]}]"#
        let lines = events.map { "    \"\($0)\": \(entry)" } + toolEvents.map { "    \"\($0)\": \(toolEntry)" }
        return "{\n  \"hooks\": {\n" + lines.joined(separator: ",\n") + "\n  }\n}"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Settings section that tells why no agent sessions show up: app location, hook configs, last event per agent.
private struct AgentHooksDiagnostics: View {
    @ObservedObject private var agents = AgentActivityManager.shared
    @State private var installed: (claude: Bool, codex: Bool)?

    var body: some View {
        Section {
            if Bundle.main.bundlePath != installedAppPath {
                row(ok: false, "App is not in /Applications", detail: "Hooks point to the copy at \(installedAppPath)")
            }
            ForEach([AgentSession.Source.claude, .codex], id: \.self) { source in
                HStack {
                    AgentSourceBadge(source: source, size: 16)
                    Text(source.displayName)
                    Spacer()
                    status(for: source)
                }
            }
        } header: {
            HStack {
                Text("Hook diagnostics")
                Spacer()
                Button("Recheck") { Task { await check() } }
                    .buttonStyle(.borderless)
            }
        } footer: {
            Text("Codex runs new hooks only after you approve them once in Codex. Events are counted since Boring Notch launched.")
        }
        .task { await check() }
    }

    @ViewBuilder
    private func status(for source: AgentSession.Source) -> some View {
        let configured = source == .claude ? installed?.claude : installed?.codex
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if let last = agents.lastEventAt[source] {
                label(ok: true, String(localized: "Last event \(compactDuration(context.date.timeIntervalSince(last))) ago"))
            } else if configured == false {
                label(ok: false, source == .claude
                    ? String(localized: "Hooks not found in ~/.claude/settings.json")
                    : String(localized: "Hooks not found in ~/.codex/hooks.json"))
            } else if configured == true {
                label(ok: nil, String(localized: "Hooks installed, no events yet"))
            } else {
                label(ok: nil, String(localized: "Checking…"))
            }
        }
    }

    private func label(ok: Bool?, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok == true ? .green : ok == false ? .red : .secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func row(ok: Bool, _ title: String, detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func check() async {
        installed = await XPCHelperClient.shared.agentHooksInstalled()
    }
}
