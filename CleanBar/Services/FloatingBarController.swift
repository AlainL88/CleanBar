import Cocoa
import SwiftUI

/// Manages a floating glass bar-shelf panel presented underneath the menu bar during hover.
@MainActor
public final class FloatingBarController: NSObject {
    private var panel: NSPanel?

    public override init() {
        super.init()
    }

    /// Shows or hides the floating bar-shelf panel positioned relative to the target status item.
    public func setVisible(_ visible: Bool, relativeTo button: NSStatusBarButton?) {
        if visible {
            showPanel(relativeTo: button)
        } else {
            hidePanel()
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton?) {
        guard let button = button, let window = button.window, let screen = window.screen else { return }

        let buttonFrameInScreen = window.convertToScreen(button.frame)

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 42),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = false

            let visualEffect = NSVisualEffectView()
            visualEffect.blendingMode = .behindWindow
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 10
            visualEffect.layer?.masksToBounds = true

            p.contentView = visualEffect
            self.panel = p
        }

        // Position panel right below the Eye icon button
        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = 42
        let panelX = max(10, min(screen.frame.width - panelWidth - 10, buttonFrameInScreen.midX - (panelWidth / 2)))
        let panelY = buttonFrameInScreen.minY - panelHeight - 6

        panel?.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel?.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }
}
