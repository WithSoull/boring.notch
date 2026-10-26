//
//  SnippetsView.swift
//  boringNotch
//
//  Notch tab with frequently used text: click a chip to copy its value.
//

import Defaults
import SwiftUI

struct SnippetsView: View {
    @Default(.snippets) private var snippets
    @Default(.clipboardHistoryEnabled) private var clipboardHistoryEnabled
    @State private var copiedID: Snippet.ID?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            pinned
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if clipboardHistoryEnabled {
                ClipboardHistoryList()
                    .frame(width: 230)
            }
        }
    }

    private var pinned: some View {
        Group {
            if snippets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.title2)
                    Text("No snippets yet")
                    Button("Add in Settings") {
                        SettingsWindowController.shared.showWindow()
                    }
                    .buttonStyle(.bordered)
                }
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(snippets) { snippet in
                            chip(snippet)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 4)
    }

    private func chip(_ snippet: Snippet) -> some View {
        let copied = copiedID == snippet.id
        return Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snippet.value, forType: .string)
            withAnimation(.smooth) { copiedID = snippet.id }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.smooth) {
                    if copiedID == snippet.id { copiedID = nil }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : Self.icon(for: snippet.value))
                    .foregroundStyle(copied ? .green : .gray)
                    .frame(width: 14)
                Text(snippet.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(copied ? 0.16 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(snippet.value)
    }

    static func icon(for value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("@") && !lower.hasPrefix("http") { return "envelope" }
        if lower.hasPrefix("http") || lower.contains(".com/") || lower.hasPrefix("t.me/") { return "link" }
        if lower.filter(\.isNumber).count >= 7 { return "phone" }
        return "text.quote"
    }
}

/// Recent clipboard entries: click to copy again, pin to keep as a snippet.
struct ClipboardHistoryList: View {
    @ObservedObject private var history = ClipboardHistoryManager.shared
    @Default(.snippets) private var snippets
    @State private var copied: String?
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.gray)
                Spacer()
                if !history.items.isEmpty {
                    Button("Clear") { history.clear() }
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .buttonStyle(PlainButtonStyle())
                }
            }
            if history.items.isEmpty {
                Text("Copied text will appear here")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(history.items, id: \.self) { item in
                            row(item)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.top, 4)
    }

    private func row(_ item: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: copied == item ? "checkmark" : SnippetsView.icon(for: item))
                .foregroundStyle(copied == item ? .green : .gray)
                .frame(width: 12)
            Text(item.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if hovered == item {
                Button {
                    snippets.append(Snippet(title: String(item.prefix(24)), value: item))
                } label: {
                    Image(systemName: "pin")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Pin as snippet")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hovered == item ? 0.1 : 0.05)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
        .onTapGesture {
            history.copy(item)
            withAnimation(.smooth) { copied = item }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.smooth) {
                    if copied == item { copied = nil }
                }
            }
        }
        .help(item)
    }
}
