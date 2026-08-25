import Cocoa
import SwiftUI

/// Manages a floating glass bar-shelf panel presented underneath the menu bar during hover.
@MainActor
public final class FloatingBarController: NSObject {
    private var panel: NSPanel?
    private weak var observer: StatusBarObserver?

    public override init() {
        super.init()
    }

    public func configure(observer: StatusBarObserver) {
        self.observer = observer
    }

    /// Shows or hides the floating bar-shelf panel, right-aligned with the CleanBar Eye button.
    public func setVisible(_ visible: Bool, relativeTo button: NSStatusBarButton?, observer: StatusBarObserver? = nil) {
        if let obs = observer {
            self.observer = obs
        }

        if visible {
            showPanel(relativeTo: button)
        } else {
            hidePanel()
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton?) {
        guard let button = button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main,
              let observer = observer else { return }

        let buttonFrameInScreen = window.convertToScreen(button.frame)

        let hiddenItems = observer.discoveredItems.filter { $0.category == .hiddenOnHover || $0.category == .deepHidden }
        let displayCount = max(1, hiddenItems.isEmpty ? observer.discoveredItems.count : hiddenItems.count)
        let panelWidth = max(120.0, CGFloat(displayCount * 36 + 28))
        let panelHeight: CGFloat = 46.0

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = NSColor.clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = false

            let hostingView = NSHostingView(rootView: FloatingBarView(observer: observer))
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 12
            hostingView.layer?.masksToBounds = true

            let visualEffect = NSVisualEffectView()
            visualEffect.blendingMode = .behindWindow
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 12
            visualEffect.layer?.masksToBounds = true

            visualEffect.addSubview(hostingView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
            ])

            p.contentView = visualEffect
            self.panel = p
        }

        // Align panel's right edge with the Eye icon's right edge
        let eyeRightX = buttonFrameInScreen.maxX
        let panelX = max(10, min(screen.frame.width - panelWidth - 10, eyeRightX - panelWidth))
        let panelY = buttonFrameInScreen.minY - panelHeight - 6

        panel?.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel?.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }
}
