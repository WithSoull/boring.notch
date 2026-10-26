//
//  AmphetamineManager.swift
//  boringNotch
//
//  Controls Amphetamine (com.if.Amphetamine) through its AppleScript dictionary.
//

import AppKit
import Combine
import Defaults

@MainActor
final class AmphetamineManager: ObservableObject {
    static let shared = AmphetamineManager()
    static let bundleID = "com.if.Amphetamine"

    @Published private(set) var isInstalled = false
    @Published private(set) var isActive = false
    /// Seconds left in the current session; 0 means unlimited.
    @Published private(set) var timeRemaining: Int = 0
    /// True when the current session was started automatically for running agents.
    @Published private(set) var startedForAgents = false

    private let scriptQueue = DispatchQueue(label: "boringNotch.amphetamine")
    private var pollTimer: Timer?

    private init() {
        isInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
        guard isInstalled else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in AmphetamineManager.shared.refresh() }
        }
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func refresh() {
        guard isInstalled else { return }
        // Don't launch Amphetamine just to ask for its status.
        guard isRunning else {
            apply(active: false, remaining: 0)
            return
        }
        run("""
            tell application id "\(Self.bundleID)"
                if session is active then
                    return (session time remaining) as text
                end if
                return "-1"
            end tell
            """) { [weak self] result in
            guard let self else { return }
            let remaining = Int(result ?? "-1") ?? -1
            self.apply(active: remaining >= 0, remaining: max(remaining, 0))
        }
    }

    /// Starts a session. `minutes == nil` means unlimited.
    func start(minutes: Int? = nil, forAgents: Bool = false) {
        let options = minutes.map { "{duration:\($0), interval:minutes, displaySleepAllowed:true}" }
            ?? "{duration:0, interval:0, displaySleepAllowed:true}"
        run("tell application id \"\(Self.bundleID)\" to start new session with options \(options)") { [weak self] _ in
            self?.startedForAgents = forAgents
            self?.refresh()
        }
    }

    func stop() {
        run("tell application id \"\(Self.bundleID)\" to end session") { [weak self] _ in
            self?.startedForAgents = false
            self?.refresh()
        }
    }

    func toggle() {
        isActive ? stop() : start()
    }

    private func apply(active: Bool, remaining: Int) {
        if !active { startedForAgents = false }
        if isActive != active { isActive = active }
        if timeRemaining != remaining { timeRemaining = remaining }
    }

    private func run(_ source: String, completion: @escaping @Sendable @MainActor (String?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("Amphetamine AppleScript error: \(error)")
            }
            let value = error == nil ? output?.stringValue : nil
            Task { @MainActor in completion(value) }
        }
    }
}
