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

/// Horizontal row of compact cards, one per account: "% left" for the 5-hour window (with time to reset) and the week.
struct UsageLimitsStrip: View {
    @ObservedObject private var manager = UsageLimitsManager.shared

    var body: some View {
        if !manager.limits.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(manager.limits) { UsageLimitCard(item: $0) }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct UsageLimitCard: View {
    let item: UsageLimits

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    AgentSourceBadge(source: item.agent, size: 12)
                    Text(item.title)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if item.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    } else if item.resetCredits > 0 {
                        Text("⟲\(item.resetCredits)")
                            .foregroundStyle(.gray)
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))

                HStack(spacing: 6) {
                    windowText("5h", item.fiveHour, now: context.date, showsReset: true)
                    windowText("W", item.week, now: context.date, showsReset: false)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 118, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
            .help(tooltip(now: context.date))
        }
    }

    private func windowText(_ label: String, _ window: UsageWindow?, now: Date, showsReset: Bool) -> Text {
        guard let window else { return Text("\(label) —").foregroundColor(.gray) }
        var text = Text("\(label) ").foregroundColor(.gray)
            + Text("\(window.remainingPercent)%").foregroundColor(usageColor(remaining: window.remainingPercent, stale: window.isStale))
        if showsReset, let resetsAt = window.resetsAt, resetsAt > now {
            text = text + Text(" \(shortDuration(resetsAt.timeIntervalSince(now)))").foregroundColor(.gray)
        }
        return text
    }

    private func tooltip(now: Date) -> String {
        var lines = [item.title]
        for (name, window) in [(String(localized: "5 hours"), item.fiveHour), (String(localized: "Week"), item.week)] {
            guard let window else { continue }
            var line = "\(name): \(window.remainingPercent)% left"
            if let resetsAt = window.resetsAt {
                line += window.isStale
                    ? " · reset, refreshing"
                    : " · resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))"
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

    var body: some View {
        Section {
            Defaults.Toggle(key: .showUsageLimits) { Text("Show Claude and Codex limits in the Agents tab") }
            Defaults.Toggle(key: .usageLimitWarnings) {
                Text("Warn in the closed notch when a 5-hour limit drops to \(UsageLimitsManager.warningThreshold)%")
            }

            HStack {
                AgentSourceBadge(source: .claude, size: 16)
                Text("Claude")
                Spacer()
                status(for: manager.limits.first { $0.id == "claude" })
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
            Text("Claude limits come from `claude -p /usage` (no model request). Each Codex account is its own CODEX_HOME folder, read through the local `codex app-server`; \"Sign in\" opens the official ChatGPT login in your browser. Tokens stay with the CLIs.")
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
