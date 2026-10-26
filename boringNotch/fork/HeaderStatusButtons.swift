//
//  HeaderStatusButtons.swift
//  boringNotch
//
//  VPN and Amphetamine controls shown on the right side of the open notch header.
//

import Defaults
import SwiftUI

struct HeaderStatusButtons: View {
    @ObservedObject private var vpn = VPNManager.shared
    @ObservedObject private var amphetamine = AmphetamineManager.shared
    @Default(.showVPNStatus) private var showVPNStatus
    @Default(.showAmphetamineButton) private var showAmphetamineButton

    var body: some View {
        HStack(spacing: 4) {
            if showVPNStatus && vpn.status != .notFound {
                Button(action: vpn.toggle) {
                    HStack(spacing: 4) {
                        switch vpn.status {
                        case .connected:
                            Text(vpn.flag ?? "🌐")
                            Text(vpn.countryCode ?? "VPN")
                                .foregroundStyle(.white)
                        case .connecting, .disconnecting:
                            ProgressView()
                                .controlSize(.mini)
                            Text("VPN")
                        default:
                            Image(systemName: "shield.slash")
                            Text("VPN")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(vpn.status == .connected ? Color.green.opacity(0.18) : Color.white.opacity(0.08)))
                }
                .buttonStyle(PlainButtonStyle())
                .help(vpn.status == .connected ? "Disconnect VPN" : "Connect VPN")
            }

            if showAmphetamineButton && amphetamine.isInstalled {
                Button(action: amphetamine.toggle) {
                    Capsule()
                        .fill(.black)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: amphetamine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                                .foregroundColor(amphetamine.isActive ? .orange : .white)
                                .imageScale(.medium)
                        }
                }
                .buttonStyle(PlainButtonStyle())
                .help(amphetamine.isActive ? "End Amphetamine session" : "Start Amphetamine session")
            }
        }
        .onAppear {
            vpn.refresh()
            amphetamine.refresh()
        }
    }
}
