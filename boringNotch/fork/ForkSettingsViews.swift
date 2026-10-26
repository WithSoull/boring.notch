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
    @Default(.clipboardHistoryEnabled) private var clipboardHistoryEnabled

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
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("Show recent clipboard text")
                }
                .onChange(of: clipboardHistoryEnabled) { _, enabled in
                    enabled ? ClipboardHistoryManager.shared.start() : ClipboardHistoryManager.shared.stop()
                }
                KeyboardShortcuts.Recorder("Open Snippets tab:", name: .openSnippets)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Keeps the last 20 copied texts in memory only; they are gone after a restart. Passwords copied from password managers are skipped.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Snippets")
    }
}

struct AgentsAndStatusSettings: View {
    @ObservedObject private var amphetamine = AmphetamineManager.shared
    @Default(.vpnServiceName) private var vpnServiceName
    @Default(.agentFolderApp) private var agentFolderApp
    @State private var copiedClaude = false
    @State private var copiedCodex = false

    private let hookPath = "/Applications/Boring Notch.app/Contents/Resources/agent-hook.sh"

    var body: some View {
        Form {
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
                    Text("Codex notify (replace `notify` in ~/.codex/config.toml; append the old notify command after \"codex\" to keep it)")
                    Spacer()
                    Button(copiedCodex ? "Copied" : "Copy") {
                        copy(codexNotify)
                        copiedCodex = true
                    }
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Hooks call the script bundled with this app, which reports events back via boringnotch:// links. Codex only reports finished turns.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Agents & Status")
    }

    private var claudeHooks: String {
        let command = "/bin/sh '\(hookPath)' claude"
        let entry = #"[{"hooks":[{"type":"command","command":"\#(command)"}]}]"#
        let toolEntry = #"[{"matcher":"*","hooks":[{"type":"command","command":"\#(command)"}]}]"#
        return """
        {
          "hooks": {
            "UserPromptSubmit": \(entry),
            "Stop": \(entry),
            "Notification": \(entry),
            "SessionEnd": \(entry),
            "PostToolUse": \(toolEntry)
          }
        }
        """
    }

    private var codexNotify: String {
        #"notify = ["/bin/sh", "\#(hookPath)", "codex"]"#
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
