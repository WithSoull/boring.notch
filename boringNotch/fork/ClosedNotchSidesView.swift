//
//  ClosedNotchSidesView.swift
//  boringNotch
//

import SwiftUI

/// Width of each side "wing" around the physical notch for compact live activities.
let closedNotchSideWidth: CGFloat = 165

/// Compact live activity layout for the closed notch: content to the left and right of the physical notch.
struct ClosedNotchSidesView<Leading: View, Trailing: View>: View {
    @EnvironmentObject var vm: BoringViewModel
    /// Adds the muted-microphone badge at the trailing end.
    var showsMicBadge = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) { leading }
                .frame(width: closedNotchSideWidth, alignment: .leading)
                .padding(.leading, 6)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 12)

            HStack(spacing: 6) {
                trailing
                if showsMicBadge { MicMutedBadge() }
            }
                .frame(width: closedNotchSideWidth, alignment: .trailing)
                .padding(.trailing, 6)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct UpcomingEventActivity: View {
    let event: EventModel
    /// Album art of the playing track, shown instead of the calendar dot.
    var albumArt: NSImage?
    var agentsWorking = false

    var body: some View {
        ClosedNotchSidesView {
            if let albumArt {
                Image(nsImage: albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .topTrailing) {
                        if agentsWorking {
                            AgentWorkingDot(size: 6, outlined: true)
                                .offset(x: 2, y: -2)
                        }
                    }
            } else {
                Circle()
                    .fill(Color(event.calendar.color))
                    .frame(width: 7, height: 7)
            }
            Text(event.title)
                .truncationMode(.tail)
        } trailing: {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                Text(countdown(at: context.date))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
            }
            Image(systemName: "calendar")
                .foregroundStyle(Color(event.calendar.color))
        }
    }

    private func countdown(at date: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(date) / 60).rounded(.up))
        return minutes <= 0 ? String(localized: "now") : String(localized: "in \(minutes) min")
    }
}
