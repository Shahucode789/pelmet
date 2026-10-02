// MenuBarInkBroadcast.swift
// Tells the apps whose icons Pelmet hides what colour the bar's items draw
// in. The bar's ink follows the wallpaper, not Dark Mode, and the only
// public reading of it is a drawn status item's `effectiveAppearance` —
// under the assertion a hidden item is drawn by nobody, so its owner is
// blind (Sconce's status band stayed white on a light wallpaper,
// 2026-10-02). The chevron is never hidden, so its appearance is the bar's,
// and it is posted whenever it flips.
//
// Protocol (any app may listen or post; sandboxed apps receive named
// distributed notifications, but never their `userInfo`):
// `com.fif7y.MenuBarInk` carries "dark" (white items) or "light", a space,
// and the poster's bundle id as its object — the listener watches that app
// quit to know the readings stopped; `com.fif7y.MenuBarInk.request` asks
// for a post now.

import AppKit

@MainActor
final class MenuBarInkBroadcast {
    static let shared = MenuBarInkBroadcast()

    static let ink = Notification.Name("com.fif7y.MenuBarInk")
    static let request = Notification.Name("com.fif7y.MenuBarInk.request")

    private weak var button: NSStatusBarButton?
    private var observation: NSKeyValueObservation?
    private var isDark: Bool?

    private init() {
        _ = DistributedNotificationCenter.default().addObserver(
            forName: Self.request, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { MenuBarInkBroadcast.shared.post() }
        }
        // The chevron's window exists only once the item is placed, and an
        // appearance set before that fires no KVO — re-read on occlusion.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let broadcast = MenuBarInkBroadcast.shared
                if let button = broadcast.button { broadcast.read(button) }
            }
        }
    }

    /// Follows the chevron. Mid-update a button briefly wears the app's
    /// own appearance (DarkAqua); only vibrant readings count.
    func track(_ button: NSStatusBarButton) {
        self.button = button
        observation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { button, _ in
            MainActor.assumeIsolated { MenuBarInkBroadcast.shared.read(button) }
        }
    }

    /// The chevron is leaving the bar (icon-hidden mode): nothing to read.
    func stop() {
        observation = nil
        button = nil
    }

    private func read(_ button: NSStatusBarButton) {
        guard let window = button.window, window.frame.height > 0,
              window.occlusionState.contains(.visible) else { return }
        let dark: Bool
        switch button.effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight, .darkAqua, .aqua]) {
        case .vibrantDark?: dark = true
        case .vibrantLight?: dark = false
        default: return
        }
        guard dark != isDark else { return }
        isDark = dark
        post()
    }

    private func post() {
        guard let isDark else { return }
        let bundle = Bundle.main.bundleIdentifier ?? "app.fif7y.Pelmet"
        DistributedNotificationCenter.default().postNotificationName(
            Self.ink, object: (isDark ? "dark" : "light") + " " + bundle,
            userInfo: nil, deliverImmediately: true
        )
    }
}
