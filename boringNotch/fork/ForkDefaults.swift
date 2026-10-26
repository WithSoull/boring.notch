//
//  ForkDefaults.swift
//  boringNotch
//
//  Settings keys for fork-only features.
//

import Defaults
import Foundation

struct Snippet: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id = UUID()
    var title: String
    var value: String
}

extension Defaults.Keys {
    // Amphetamine
    static let showAmphetamineButton = Key<Bool>("showAmphetamineButton", default: true)
    static let autoAmphetamineForAgents = Key<Bool>("autoAmphetamineForAgents", default: true)

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

    // Shelf
    static let copyPathOnShelfDrop = Key<Bool>("copyPathOnShelfDrop", default: false)
}
