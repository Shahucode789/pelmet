// GlassPanel.swift
// The surface Pelmet's floating panels share: a borderless, non-activating
// glass panel that hangs under the menu bar. Non-activating, so the app you
// were in stays in front. It draws no border of its own: the rounded glass
// is the edge, with the system shadow re-derived whenever the frame changes
// (an earlier panel's edge read as a heavy near-black ring that ignored the
// corners, and a shadow taken before the glass had its shape is the suspect).

import AppKit

@MainActor
class GlassPanel: NSPanel {
    static let cornerRadius: CGFloat = 12
    /// The system's shadow follows the rounded glass once it is re-derived
    /// (see `place`). If a live look still shows a dark ring at the edge,
    /// this is the one switch: the glass reads fine without a shadow.
    static let usesSystemShadow = true
    static let gapBelowBar: CGFloat = 4
    static let edgeMargin: CGFloat = 8

    /// `content` fills the glass; it is the caller's to size and lay out.
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = Self.usesSystemShadow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Its size is its content's: no edge resize, no drag of the surface.
        styleMask.remove(.resizable)
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        content.translatesAutoresizingMaskIntoConstraints = false
        let host: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            host = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.cornerRadius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            host = effect
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
        }
        contentView = host
    }

    /// Move or resize, then re-derive the shadow from what is on screen.
    func place(_ frame: NSRect, display: Bool = true) {
        setFrame(frame, display: display)
        invalidateShadow()
    }

    /// The bar's own height on `screen`: the visibleFrame band, falling
    /// back to the safe area under a full-screen app.
    static func barHeight(of screen: NSScreen) -> CGFloat {
        let safeBand = screen.safeAreaInsets.top
        let visibleBand = screen.frame.maxY - screen.visibleFrame.maxY
        let band = visibleBand > 0 && (safeBand == 0 || visibleBand <= safeBand + 2) ? visibleBand : safeBand
        return band > 0 ? band : 24
    }

    /// Top edge of a panel hung under the bar on `screen` (Cocoa y).
    static func topUnderBar(of screen: NSScreen) -> CGFloat {
        screen.frame.maxY - barHeight(of: screen) - gapBelowBar
    }
}

/// A glass panel that can take keyboard focus (a text field in it types)
/// without activating the app or becoming its main window.
final class KeyableGlassPanel: GlassPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
