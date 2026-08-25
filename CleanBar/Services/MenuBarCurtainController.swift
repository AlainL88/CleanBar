import Cocoa
import SwiftUI

/// Controller managing a sleek visual curtain overlay window that cleanly covers the main menu bar region to the left of CleanBar.
@MainActor
public final class MenuBarCurtainController: NSObject {
    public static let shared = MenuBarCurtainController()

    private var curtainWindow: NSWindow?
    public private(set) var isCurtainActive: Bool = false

    public override init() {
        super.init()
    }

    /// Updates or activates the curtain to cover the menu bar strictly to the left of CleanBar's Eye icon.
    public func updateCurtain(eyeX: CGFloat) {
        guard eyeX > 50.0 else { return }

        guard let screen = NSScreen.main else { return }
        let menuBarHeight: CGFloat = screen.frame.height - screen.visibleFrame.maxY
        let h = max(28.0, menuBarHeight > 0 ? menuBarHeight : 32.0)
        let curtainFrame = NSRect(x: 0, y: screen.frame.height - h, width: eyeX, height: h)

        if curtainWindow == nil {
            let win = NSWindow(
                contentRect: curtainFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            win.isOpaque = false
            win.backgroundColor = NSColor.clear
            win.hasShadow = false
            win.hidesOnDeactivate = false
            win.ignoresMouseEvents = true

            let visualEffect = NSVisualEffectView(frame: win.contentView?.bounds ?? .zero)
            visualEffect.autoresizingMask = [.width, .height]
            visualEffect.blendingMode = .withinWindow
            visualEffect.material = .headerView
            visualEffect.state = .active
            visualEffect.wantsLayer = true

            win.contentView = visualEffect
            self.curtainWindow = win
        }

        curtainWindow?.setFrame(curtainFrame, display: true)
        curtainWindow?.orderFrontRegardless()
        isCurtainActive = true
    }

    /// Hides the curtain overlay.
    public func hideCurtain() {
        curtainWindow?.orderOut(nil)
        isCurtainActive = false
    }
}
