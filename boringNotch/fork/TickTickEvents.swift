//
//  TickTickEvents.swift
//  boringNotch
//
//  Events that come from a TickTick calendar subscription open in TickTick instead of Calendar.
//

import AppKit

extension EventModel {
    static let tickTickBundleID = "com.TickTick.task.mac"

    var isFromTickTick: Bool {
        let haystack = [calendar.title, calendar.account, url?.absoluteString ?? "", notes ?? ""]
        return haystack.contains { $0.localizedCaseInsensitiveContains("ticktick") || $0.localizedCaseInsensitiveContains("dida365") }
    }

    /// Opens the event where it lives: TickTick for TickTick tasks, Calendar for everything else.
    func open() {
        if isFromTickTick,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.tickTickBundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = calendarAppURL() {
            NSWorkspace.shared.open(url)
        }
    }
}
