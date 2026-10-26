//
//  UsageLimitsViews.swift
//  boringNotch
//
//  Limits strip in the Agents tab, the closed-notch warning and the Codex accounts settings.
//

import Defaults
import SwiftUI

/// Color of a "% left" value: green, yellow at 25% and below, red at 10% and below; grey once the window has reset.
func usageColor(remaining: Int, stale: Bool = false) -> Color {
    if stale { return .gray }
    return remaining <= 10 ? .red : remaining <= 25 ? .yellow : .green
}

/// Agents tab, right column: one line per account — icon, "5h 39%" and "W 91%" left, colored. Details in the tooltip.
struct UsageLimitsList: View {
    @ObservedObject private var manager = UsageLimitsManager.shared

    var body: some View {
        if !manager.limits.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(manager.limits) { UsageLimitRow(item: $0) }
            }
        }
    }
}

private struct UsageLimitRow: View {
    let item: UsageLimits

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 6) {
                AgentSourceBadge(source: item.agent, size: 15)
                windowText("5h", item.fiveHour)
                windowText("W", item.week)
                Spacer(minLength: 0)
                if item.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else if item.resetCredits > 0 {
                    Text("⟲\(item.resetCredits)")
                        .foregroundStyle(.gray)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .contentShape(Rectangle())
            .help(tooltip(now: context.date))
        }
    }

    private func windowText(_ label: String, _ window: UsageWindow?) -> Text {
        guard let window else { return Text("\(label) —").foregroundColor(.gray) }
        return Text("\(label) ").foregroundColor(.gray)
            + Text("\(window.remainingPercent)%").foregroundColor(usageColor(remaining: window.remainingPercent, stale: window.isStale))
    }

    private func tooltip(now: Date) -> String {
        var lines = [item.title]
        for (name, window) in [(String(localized: "5 hours"), item.fiveHour), (String(localized: "Week"), item.week)] {
            guard let window else { continue }
            var line = "\(name): \(window.remainingPercent)% left"
            if let resetsAt = window.resetsAt {
                line += window.isStale
                    ? " · reset, refreshing"
                    : " · resets in \(shortDuration(resetsAt.timeIntervalSince(now))) (\(resetsAt.formatted(date: .abbreviated, time: .shortened)))"
            }
            lines.append(line)
        }
        if item.resetCredits > 0 {
            var line = String(localized: "Free resets: \(item.resetCredits)")
            if let expiry = item.nextCreditExpiry { line += " · next expires \(expiry.formatted(date: .abbreviated, time: .omitted))" }
            lines.append(line)
        }
        if let error = item.errorText { lines.append(error) }
        if let updatedAt = item.updatedAt { lines.append("Updated \(compactDuration(now.timeIntervalSince(updatedAt))) ago") }
        return lines.joined(separator: "\n")
    }
}

/// "3h2m", "48m", "6d" — coarser than compactDuration, for reset countdowns.
func shortDuration(_ interval: TimeInterval) -> String {
    let minutes = max(0, Int(interval / 60))
    if minutes >= 48 * 60 { return "\(minutes / 1440)d" }
    if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m" }
    return "\(minutes)m"
}

/// Closed-notch warning: the 5-hour window of an account is nearly or fully used up. Only the colored percent on the right.
struct UsageLimitActivity: View {
    let item: UsageLimits

    var body: some View {
        let remaining = item.fiveHour?.remainingPercent ?? 0
        ClosedNotchSidesView {
            AgentSourceBadge(source: item.agent, size: 16)
            Text(item.title)
                .truncationMode(.tail)
        } trailing: {
            Text("5h")
                .foregroundStyle(.gray)
            Text("\(remaining)%")
                .foregroundStyle(usageColor(remaining: remaining))
                .monospacedDigit()
        }
    }
}

/// Settings section: limits toggles, Claude status and the Codex accounts list.
struct UsageLimitsSettings: View {
    @Default(.codexAccounts) private var accounts
    @ObservedObject private var manager = UsageLimitsManager.shared
    @State private var signingIn: UUID?
    @State private var copiedStatusLine = false

    private static let statusLineJSON = #""statusLine": {"type": "command", "command": "/bin/sh '/Applications/Boring Notch.app/Contents/Resources/claude-statusline.sh'"}"#

    var body: some View {
        Section {
            Defaults.Toggle(key: .showUsageLimits) { Text("Show Claude and Codex limits in the Agents tab") }
            Defaults.Toggle(key: .usageLimitWarnings) {
                Text("Warn in the closed notch when a 5-hour limit drops to \(UsageLimitsManager.warningThreshold)%")
            }

            HStack {
                AgentSourceBadge(source: .claude, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude")
                    Text("claude -p /usage · optional statusLine for terminal sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                status(for: manager.limits.first { $0.id == "claude" })
                Button(copiedStatusLine ? "Copied" : "Copy statusLine") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.statusLineJSON, forType: .string)
                    copiedStatusLine = true
                }
            }

            ForEach($accounts) { $account in
                HStack {
                    AgentSourceBadge(source: .codex, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name", text: $account.name, prompt: Text(title(for: account)))
                            .textFieldStyle(.plain)
                        Text(account.home)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    status(for: manager.limits.first { $0.id == "codex-\(account.id)" })
                    Button(signingIn == account.id ? "Waiting…" : "Sign in") {
                        signIn(account)
                    }
                    .disabled(signingIn != nil)
                    if account.id != CodexAccount.main.id {
                        Button(role: .destructive) {
                            accounts.removeAll { $0.id == account.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button {
                let account = CodexAccount(name: "", home: "~/.codex-accounts/\(UUID().uuidString.prefix(8).lowercased())")
                accounts.append(account)
                signIn(account)
            } label: {
                Label("Add Codex account", systemImage: "plus")
            }
            .disabled(signingIn != nil)
        } header: {
            HStack {
                Text("Limits")
                Spacer()
                Button("Refresh") { manager.refresh(force: true) }
                    .buttonStyle(.borderless)
            }
        } footer: {
            Text("Claude limits come from `claude -p /usage` (no model request). Optionally add the copied statusLine to ~/.claude/settings.json so terminal sessions update them right after each response. Each Codex account is its own CODEX_HOME folder, read through the local `codex app-server`; \"Sign in\" opens the official ChatGPT login in your browser. Tokens stay with the CLIs.")
        }
    }

    private func title(for account: CodexAccount) -> String {
        manager.limits.first { $0.id == "codex-\(account.id)" }?.title ?? "Codex"
    }

    @ViewBuilder
    private func status(for item: UsageLimits?) -> some View {
        if let item, let error = item.errorText {
            Text(error).foregroundStyle(.secondary)
        } else if let item, let window = item.fiveHour {
            Text("5h \(window.remainingPercent)% left").foregroundStyle(.secondary)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func signIn(_ account: CodexAccount) {
        signingIn = account.id
        Task {
            _ = await manager.login(account)
            signingIn = nil
        }
    }
}
