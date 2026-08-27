import Cocoa
import SwiftUI

/// Controller managing the floating sub-bar panel displayed underneath the menu bar.
@MainActor
public final class FloatingShelfController: NSObject {
    public private(set) var panel: NSPanel?
    private weak var observer: StatusBarObserver?
    public var onOpenPreferences: (() -> Void)?
    public var onItemTriggered: ((StatusItemModel) -> Void)?
    private var tooltipPanel: NSPanel?
    private var tooltipLabel: NSTextField?

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
        onItemTriggered: ((StatusItemModel) -> Void)? = nil
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
        // Match the main menu bar height (~30pt) so the shelf feels like part of it.
        let panelHeight: CGFloat = 30.0

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            // A fixed dark shelf (opaque + dark material) so captured glyphs —
            // which adapt to the menu bar's light/dark background — always have
            // high contrast here, regardless of the desktop behind the panel.
            p.appearance = NSAppearance(named: .darkAqua)
            p.isOpaque = true
            p.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1.0)
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = false

            let shelfView = FloatingShelfView(
                observer: observer,
                onOpenPreferences: { [weak self] in
                    self?.onOpenPreferences?()
                },
                onItemClicked: { [weak self] item in
                    self?.onItemTriggered?(item)
                },
                onItemHover: { [weak self] item, frameInWindow in
                    self?.showTooltip(item: item, frameInWindow: frameInWindow)
                },
                onHoverEnd: { [weak self] in
                    self?.hideTooltip()
                }
            )

            let hostingView = NSHostingView(rootView: shelfView)
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 9
            // Don't clip: the hover tooltip extends below the panel.
            hostingView.layer?.masksToBounds = false

            let visualEffect = NSVisualEffectView()
            visualEffect.blendingMode = .withinWindow
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 9
            visualEffect.layer?.masksToBounds = false

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
        hideTooltip()
    }

    /// Shows a small floating label under the hovered tile with the app name and,
    /// when available, the account/subtitle from the item's AX title.
    private func showTooltip(item: StatusItemModel, frameInWindow: CGRect) {
        guard let window = panel, window.isVisible else { return }
        let text: String
        if item.subtitle.isEmpty {
            text = item.appName
        } else if item.subtitle.hasPrefix(item.appName) {
            text = item.subtitle
        } else {
            text = "\(item.appName) — \(item.subtitle)"
        }
        NSLog("🪟 tooltip: '\(text)' app='\(item.appName)' subtitle='\(item.subtitle)'")

        if tooltipPanel == nil {
            let tp = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            tp.level = .floating
            tp.isOpaque = false
            tp.backgroundColor = .clear
            tp.hasShadow = true
            tp.ignoresMouseEvents = true
            tp.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            // Solid dark background guarantees contrast on any desktop.
            let container = NSView()
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor
            container.layer?.cornerRadius = 5
            container.layer?.masksToBounds = true
            container.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3)
            ])
            tp.contentView = container
            self.tooltipPanel = tp
            self.tooltipLabel = label
        }

        tooltipLabel?.stringValue = text
        tooltipLabel?.sizeToFit()
        let labelSize = tooltipLabel?.frame.size ?? NSSize(width: 60, height: 16)
        let w = min(260, labelSize.width + 16)
        let h = labelSize.height + 6
        // Position from the mouse (always in correct screen coords, bottom-left):
        // the tile frame conversion was landing the tooltip inside the shelf.
        let mouse = NSEvent.mouseLocation
        let x = mouse.x - w / 2
        let y = mouse.y - h - 8
        tooltipPanel?.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        tooltipPanel?.orderFrontRegardless()
    }

    private func hideTooltip() {
        tooltipPanel?.orderOut(nil)
    }
}
