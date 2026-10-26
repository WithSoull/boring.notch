//
//  ClosedNotchSidesView.swift
//  boringNotch
//

import SwiftUI

/// Width of each side "wing" around the physical notch for compact live activities.
let closedNotchSideWidth: CGFloat = 130

/// Compact live activity layout for the closed notch: content to the left and right of the physical notch.
struct ClosedNotchSidesView<Leading: View, Trailing: View>: View {
    @EnvironmentObject var vm: BoringViewModel
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

            HStack(spacing: 6) { trailing }
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

    var body: some View {
        ClosedNotchSidesView {
            Circle()
                .fill(Color(event.calendar.color))
                .frame(width: 7, height: 7)
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
