import Cocoa
import SwiftUI

/// Single status item controller managing the permanent CleanBar Eye icon, floating bar-shelf, and popover launchers.
@MainActor
public final class MenuBarSpacerController: NSObject {
    public private(set) var statusItem: NSStatusItem?
    public private(set) var isExpanded: Bool = false
    public private(set) var floatingBarController = FloatingBarController()
    public var onToggle: ((Bool) -> Void)?
    public var isPopoverShown: Bool {
        return preferencesPopover?.isShown == true
    }
    private var preferencesPopover: NSPopover?
    private weak var observer: StatusBarObserver?
    private weak var stateStore: StateStore?

    public init(observer: StatusBarObserver? = nil, stateStore: StateStore? = nil) {
        self.observer = observer
        self.stateStore = stateStore
        super.init()
        setupStatusItem()
    }

    public func configure(observer: StatusBarObserver, stateStore: StateStore) {
        self.observer = observer
        self.stateStore = stateStore
    }

    private func setupStatusItem() {
        // Create 1 single, permanent status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "CleanBar")
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Initial state: expanded to 24.0
        statusItem?.length = 24.0
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            openPreferences()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(sender)
        } else {
            openPreferences()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let guideItem = NSMenuItem(title: "Setup Guide...", action: #selector(openOnboarding), keyEquivalent: "g")
        guideItem.target = self
        menu.addItem(guideItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit CleanBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.popUpMenu(menu)
    }

    @objc public func openPreferences() {
        guard let observer = observer, let stateStore = stateStore, let button = statusItem?.button else { return }

        if preferencesPopover?.isShown == true {
            preferencesPopover?.close()
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let settingsView = SettingsView(
            observer: observer,
            stateStore: stateStore,
            onShowInstructions: { [weak self] in
                self?.preferencesPopover?.close()
                self?.openOnboarding()
            }
        )

        popover.contentViewController = NSHostingController(rootView: settingsView)
        self.preferencesPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openOnboarding() {
        guard let stateStore = stateStore, let button = statusItem?.button else { return }

        if preferencesPopover?.isShown == true {
            preferencesPopover?.close()
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let onboardingView = OnboardingView(onDismiss: { [weak popover, stateStore] in
            stateStore.hasCompletedOnboarding = true
            popover?.close()
        })

        popover.contentViewController = NSHostingController(rootView: onboardingView)
        self.preferencesPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc public func toggleExpansion() {
        setExpanded(!isExpanded)
        onToggle?(isExpanded)
    }

    /// Dynamically calculates the exact collapse length needed to fill the gap
    /// between CleanBar's Eye icon and the left menu boundary/notch.
    public func calculateAvailableGap() -> CGFloat {
        guard let buttonWindow = statusItem?.button?.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            return 600.0
        }

        let eyeX = buttonWindow.frame.origin.x

        var leftBoundaryX: CGFloat = 350.0
        if #available(macOS 12.0, *) {
            if let auxiliaryTopLeftArea = screen.auxiliaryTopLeftArea, auxiliaryTopLeftArea.width > 0 {
                leftBoundaryX = max(leftBoundaryX, auxiliaryTopLeftArea.width)
            }
        }

        return eyeX - leftBoundaryX
    }

    public func setExpanded(_ expanded: Bool, hiddenItemsCount: Int = 0, style: BarShelfStyle = .auto) {
        let gap = calculateAvailableGap()
        let isSpaceTight = (gap < 450.0)

        let useFloatingPanel: Bool = {
            switch style {
            case .inline:
                return false
            case .floating:
                return true
            case .auto:
                return isSpaceTight
            }
        }()

        let collapseLength = max(400.0, min(gap, (NSScreen.main?.frame.width ?? 1400.0) - 350.0))
        let targetLength: CGFloat = expanded ? 24.0 : collapseLength

        guard self.isExpanded != expanded || statusItem?.length != targetLength else { return }
        self.isExpanded = expanded

        guard let button = statusItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: expanded ? "eye.fill" : "eye.slash",
            accessibilityDescription: "CleanBar"
        )

        if statusItem?.length != targetLength {
            statusItem?.length = targetLength
        }

        // Floating Bar-Shelf handling
        if expanded && useFloatingPanel {
            floatingBarController.setVisible(true, relativeTo: button)
        } else {
            floatingBarController.setVisible(false, relativeTo: button)
        }
    }
}
