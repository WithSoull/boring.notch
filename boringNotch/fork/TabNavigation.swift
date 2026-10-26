//
//  TabNavigation.swift
//  boringNotch
//
//  Switch notch tabs with a two-finger horizontal swipe.
//

import AppKit
import Defaults
import SwiftUI

extension BoringViewCoordinator {
    var visibleTabs: [TabModel] {
        tabs.filter { $0.view != .shelf || Defaults[.boringShelf] }
    }

    /// Moves to the next (+1) or previous (-1) tab, without wrapping around.
    func switchTab(by step: Int) {
        let views = visibleTabs.map(\.view)
        guard let index = views.firstIndex(of: currentView) else { return }
        let target = index + step
        guard views.indices.contains(target) else { return }
        withAnimation(.smooth) {
            currentView = views[target]
        }
    }
}

extension View {
    /// Two-finger horizontal trackpad swipe: fingers to the left → next tab, to the right → previous.
    func tabSwipeGesture(isEnabled: Bool, onSwipe: @escaping (Int) -> Void) -> some View {
        background(TabSwipeMonitor(isEnabled: isEnabled, onSwipe: onSwipe))
    }
}

private struct TabSwipeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onSwipe: onSwipe)
    }

    @MainActor final class Coordinator {
        var isEnabled: Bool
        var onSwipe: (Int) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var fired = false
        private let threshold: CGFloat = 70

        init(isEnabled: Bool, onSwipe: @escaping (Int) -> Void) {
            self.isEnabled = isEnabled
            self.onSwipe = onSwipe
        }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self, event.window === view?.window else { return event }
                self.handle(event)
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            // Trackpad gestures only; ignore momentum so one swipe moves one tab.
            guard event.hasPreciseScrollingDeltas, event.momentumPhase == [] else { return }
            if event.phase == .began || event.phase == .mayBegin {
                accumulated = 0
                fired = false
            }
            if event.phase == .ended || event.phase == .cancelled {
                accumulated = 0
                fired = false
                return
            }
            guard isEnabled, !fired else { return }
            guard abs(event.scrollingDeltaX) > 1.5 * abs(event.scrollingDeltaY) else { return }

            // Normalize to finger movement regardless of the natural scrolling setting.
            let fingerDelta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            accumulated += fingerDelta
            if abs(accumulated) >= threshold {
                fired = true
                onSwipe(accumulated < 0 ? 1 : -1)
            }
        }
    }
}
