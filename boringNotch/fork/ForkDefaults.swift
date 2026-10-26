//
//  ForkDefaults.swift
//  boringNotch
//
//  Settings keys for fork-only features.
//

import Defaults
import Foundation
import KeyboardShortcuts

struct Snippet: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id = UUID()
    var title: String
    var value: String
}

/// A Codex account is a separate CODEX_HOME folder signed in through the official login.
struct CodexAccount: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id = UUID()
    /// Display name; empty means the account's email.
    var name: String
    var home: String

    static let main = CodexAccount(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!, name: "", home: "~/.codex")
}

extension Defaults.Keys {
    // Amphetamine
    static let showAmphetamineButton = Key<Bool>("showAmphetamineButton", default: true)
    static let autoAmphetamineForAgents = Key<Bool>("autoAmphetamineForAgents", default: true)
    /// Whether the running Amphetamine session was started automatically for agents (survives app restarts).
    static let amphetamineStartedForAgents = Key<Bool>("amphetamineStartedForAgents", default: false)

    // VPN
    static let showVPNStatus = Key<Bool>("showVPNStatus", default: true)
    static let vpnServiceName = Key<String>("vpnServiceName", default: "Happ Plus")

    // Snippets
    static let snippets = Key<[Snippet]>("snippets", default: [])

    // Agents
    static let showAgentBanners = Key<Bool>("showAgentBanners", default: true)
    static let showWorkingAgentsIndicator = Key<Bool>("showWorkingAgentsIndicator", default: true)
    /// App used to open an agent's folder; empty means Finder.
    static let agentFolderApp = Key<String>("agentFolderApp", default: "")

    static let showPeripheralBatteries = Key<Bool>("showPeripheralBatteries", default: true)
    static let showMicrophoneButton = Key<Bool>("showMicrophoneButton", default: true)

    /// Now Playing apps the notch follows (bundle IDs); empty means any app.
    static let mediaSourceBundleIDs = Key<[String]>("mediaSourceBundleIDs", default: [])

    // Subscription limits
    static let showUsageLimits = Key<Bool>("showUsageLimits", default: true)
    /// Closed-notch warning when a 5-hour window is nearly used up.
    static let usageLimitWarnings = Key<Bool>("usageLimitWarnings", default: true)
    static let codexAccounts = Key<[CodexAccount]>("codexAccounts", default: [.main])

    // Shelf
    static let copyPathOnShelfDrop = Key<Bool>("copyPathOnShelfDrop", default: false)
}

extension KeyboardShortcuts.Name {
    static let toggleMicrophoneMute = Self("toggleMicrophoneMute", default: .init(.m, modifiers: [.control, .option, .command]))
    static let openSnippets = Self("openSnippets", default: .init(.v, modifiers: [.control, .command]))
}
