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
    @State private var copiedID: Snippet.ID?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
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

