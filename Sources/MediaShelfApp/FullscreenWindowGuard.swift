import AppKit
import SwiftUI

/// Keeps content and video-size changes from altering an AppKit fullscreen window.
struct FullscreenWindowGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> FullscreenWindowObserverView {
        FullscreenWindowObserverView()
    }

    func updateNSView(_ nsView: FullscreenWindowObserverView, context: Context) {}
}

final class FullscreenWindowObserverView: NSView {
    private var observedWindow: NSWindow?
    private var observationTokens: [NSObjectProtocol] = []
    private var isRestoringFrame = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window !== observedWindow else { return }
        stopObserving()
        observedWindow = window
        guard let window else { return }

        let center = NotificationCenter.default
        observationTokens = [
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.restoreFullscreenFrameIfNeeded() }
            },
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.restoreFullscreenFrameIfNeeded()
            }
        ]
    }

    deinit {
        stopObserving()
    }

    private func restoreFullscreenFrameIfNeeded() {
        guard !isRestoringFrame,
              let window = observedWindow,
              window.styleMask.contains(.fullScreen),
              let fullscreenFrame = window.screen?.frame,
              !NSEqualRects(window.frame, fullscreenFrame)
        else { return }

        isRestoringFrame = true
        window.setFrame(fullscreenFrame, display: true, animate: false)
        isRestoringFrame = false
    }

    private func stopObserving() {
        observationTokens.forEach(NotificationCenter.default.removeObserver)
        observationTokens.removeAll()
        observedWindow = nil
    }
}
