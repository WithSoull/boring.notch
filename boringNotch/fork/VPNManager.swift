//
//  VPNManager.swift
//  boringNotch
//
//  Real VPN state from the system (scutil --nc via the XPC helper) and exit country from the public IP.
//

import Combine
import Defaults
import Foundation

@MainActor
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    enum Status: Equatable {
        case unknown
        case connected
        case connecting
        case disconnected
        case disconnecting
        case notFound
    }

    @Published private(set) var status: Status = .unknown
    /// ISO 3166 alpha-2 code of the current public IP, e.g. "NL".
    @Published private(set) var countryCode: String?

    private var pollTimer: Timer?
    private var countryTimer: Timer?
    private var isBusy = false

    private init() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in VPNManager.shared.refresh() }
        }
        countryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await VPNManager.shared.refreshCountry() }
        }
    }

    var flag: String? {
        guard let code = countryCode, code.count == 2 else { return nil }
        let base: UInt32 = 0x1F1E6 - 65
        return String(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }.map(Character.init))
    }

    func refresh() {
        guard Defaults[.showVPNStatus] else { return }
        Task {
            let raw = await XPCHelperClient.shared.vpnStatus(serviceName: Defaults[.vpnServiceName])
            let newStatus = Self.parse(raw)
            if newStatus != status {
                status = newStatus
                if newStatus == .connected || newStatus == .disconnected {
                    await refreshCountry()
                }
            }
        }
    }

    func toggle() {
        guard !isBusy else { return }
        let connect = status != .connected && status != .connecting
        isBusy = true
        status = connect ? .connecting : .disconnecting
        Task {
            _ = await XPCHelperClient.shared.setVPNConnected(serviceName: Defaults[.vpnServiceName], connected: connect)
            isBusy = false
            refresh()
        }
    }

    func refreshCountry() async {
        // Give the tunnel a moment to settle after a state change.
        try? await Task.sleep(for: .seconds(1))
        guard let url = URL(string: "https://api.country.is/") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        struct Response: Decodable { let country: String }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            countryCode = try JSONDecoder().decode(Response.self, from: data).country
        } catch {
            countryCode = nil
        }
    }

    private static func parse(_ raw: String?) -> Status {
        switch raw?.trimmingCharacters(in: .whitespaces) {
        case "Connected": return .connected
        case "Connecting": return .connecting
        case "Disconnected": return .disconnected
        case "Disconnecting": return .disconnecting
        case nil: return .notFound
        default: return .unknown
        }
    }
}
