//
//  BoringCalendar.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import SwiftUI

struct EventListView: View {
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            !(event.isAllDay && Defaults[.hideAllDayEvents])
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let now = Date()
        // Determine a single target using preferred search order:
        // 1) first non-all-day upcoming/in-progress event
        // 2) first all-day event
        // 3) last event (fallback)
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredEvents) { event in
                    Button(action: {
                        event.open()
                    }) {
                        eventRow(event)
                    }
                    .id(event.id)
                    .padding(.leading, -5)
                    .buttonStyle(PlainButtonStyle())
                    .listRowSeparator(.automatic)
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    .listRowSeparatorTint(.gray.opacity(0.2))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            // Background syncs keep the manual scroll position; only a different set of events (e.g. another day) scrolls.
            .onChange(of: filteredEvents.map(\.id)) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Rectangle()
                .fill(Color(event.calendar.color))
                .frame(width: 3, height: 14)
                .cornerRadius(1.5)

            Text(event.title)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(showFullEventTitles ? nil : 1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Tasks without a time (all-day) show no time label to save room.
            if !event.isAllDay {
                Text(event.start, style: .time)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.65))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 1)
        .opacity(
            event.eventStatus == .ended && !event.isAllDay && Calendar.current.isDateInToday(event.start)
                ? 0.6 : 1.0)
    }
}

#Preview {
    CompactCalendarView()
        .frame(width: 400, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}
