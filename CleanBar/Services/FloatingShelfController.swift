import Cocoa
import SwiftUI

/// Controller managing the floating sub-bar panel displayed underneath the menu bar.
@MainActor
public final class FloatingShelfController: NSObject {
    public private(set) var panel: NSPanel?
    private weak var observer: StatusBarObserver?
    public var onOpenPreferences: (() -> Void)?
    public var onItemTriggered: (() -> Void)?

    /// Returns current panel frame in screen coordinates if visible.
    public var panelFrame: CGRect? {
        guard let p = panel, p.isVisible else { return nil }
        return p.frame
    }

    public override init() {
        super.init()
    }

    public func configure(
        observer: StatusBarObserver,
        onOpenPreferences: (() -> Void)? = nil,
        onItemTriggered: (() -> Void)? = nil
    ) {
        self.observer = observer
        self.onOpenPreferences = onOpenPreferences
        self.onItemTriggered = onItemTriggered
    }

    public func setVisible(_ visible: Bool, relativeTo button: NSStatusBarButton?) {
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
        let itemsCount = observer.leftHiddenItems.count

        let itemsWidth = observer.leftHiddenItems.reduce(0.0) { $0 + max(30.0, $1.frame.width) }
        let panelWidth: CGFloat = itemsCount == 0 ? 340.0 : max(180.0, itemsWidth + 64.0)
        let panelHeight: CGFloat = 40.0

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

            let shelfView = FloatingShelfView(
                observer: observer,
                onOpenPreferences: { [weak self] in
                    self?.onOpenPreferences?()
                },
                onItemClicked: { [weak self] in
                    self?.onItemTriggered?()
                }
            )

            let hostingView = NSHostingView(rootView: shelfView)
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 9
            hostingView.layer?.masksToBounds = true

            let visualEffect = NSVisualEffectView()
            visualEffect.blendingMode = .behindWindow
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 9
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

        // Align right edge of panel with right edge of the Eye icon
        let eyeRightX = buttonFrameInScreen.maxX
        let panelX = max(10.0, min(screen.frame.width - panelWidth - 10.0, eyeRightX - panelWidth))
        let panelY = buttonFrameInScreen.minY - panelHeight - 4.0

        panel?.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel?.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }
}
