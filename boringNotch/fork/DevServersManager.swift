//
//  DevServersManager.swift
//  boringNotch
//
//  Local dev servers (listening ports of user processes), listed by the XPC helper.
//

import AppKit
import Combine

struct DevServer: Codable, Identifiable, Equatable {
    let pid: Int32
    let port: Int
    let name: String
    let cwd: String

    var id: String { "\(pid):\(port)" }

    var project: String {
        let folder = (cwd as NSString).lastPathComponent
        return folder.isEmpty || folder == "/" ? name : folder
    }
}

@MainActor
final class DevServersManager: ObservableObject {
    static let shared = DevServersManager()

    @Published private(set) var servers: [DevServer] = []

    private var timer: Timer?
    private var watchers = 0

    private init() {}

    func startWatching() {
        watchers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in DevServersManager.shared.refresh() }
        }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task {
            guard let data = await XPCHelperClient.shared.listDevServers(),
                  let list = try? JSONDecoder().decode([DevServer].self, from: data)
            else { return }
            if list != servers { servers = list }
        }
    }

    func open(_ server: DevServer) {
        if let url = URL(string: "http://localhost:\(server.port)") {
            NSWorkspace.shared.open(url)
        }
    }

    func stop(_ server: DevServer) {
        Task {
            _ = await XPCHelperClient.shared.stopDevServer(pid: server.pid)
            try? await Task.sleep(for: .milliseconds(500))
            refresh()
        }
    }
}
