//
//  CompactHomeViews.swift
//  boringNotch
//
//  Home tab layout when the calendar is shown: a narrow music column and a calendar
//  with a one-line header, so more events fit.
//

import Defaults
import SwiftUI

let compactMusicWidth: CGFloat = 116

struct CompactMusicView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 5) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                .frame(width: 68, height: 68)

            MarqueeText(
                .constant(trackLine),
                font: .caption,
                nsFont: .caption1,
                textColor: .white,
                frameWidth: compactMusicWidth
            )
            .frame(height: 14)

            progressBar

            HStack(spacing: 10) {
                HoverButton(icon: "backward.fill", scale: .small) {
                    MusicManager.shared.previousTrack()
                }
                HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .medium) {
                    MusicManager.shared.togglePlay()
                }
                HoverButton(icon: "forward.fill", scale: .small) {
                    MusicManager.shared.nextTrack()
                }
            }
        }
        .frame(width: compactMusicWidth)
        .buttonStyle(PlainButtonStyle())
    }

    private var trackLine: String {
        musicManager.artistName.isEmpty
            ? musicManager.songTitle
            : "\(musicManager.songTitle) · \(musicManager.artistName)"
    }

    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.5 : nil)) { timeline in
            let duration = max(musicManager.songDuration, 1)
            let position = MusicManager.shared.estimatedPlaybackPosition(at: timeline.date)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * min(max(position / duration, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 6)
    }
}

struct CompactCalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if EventListView.filteredEvents(events: calendarManager.events).isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title3)
                    Text(isToday ? "No events today" : "No events")
                        .font(.caption)
                }
                .foregroundStyle(Color(white: 0.65))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventListView(events: calendarManager.events)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedDate) {
            Task { await calendarManager.updateCurrentDate(selectedDate) }
        }
        .onChange(of: vm.notchState) { _, _ in
            selectedDate = Date.now
        }
        .onAppear {
            selectedDate = Date.now
            Task { await calendarManager.updateCurrentDate(Date.now) }
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if isToday {
                Text("today")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.65))
            } else {
                Button("Today") { selectedDate = Date.now }
                    .font(.caption)
                    .foregroundStyle(Color.effectiveAccent)
                    .buttonStyle(PlainButtonStyle())
            }
            Spacer(minLength: 0)
            chevron("chevron.left") { shiftDay(-1) }
            chevron("chevron.right") { shiftDay(1) }
        }
        .frame(height: 20)
    }

    private func chevron(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.65))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func shiftDay(_ days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }
}
