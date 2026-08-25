import Cocoa
import SwiftUI

/// Manages the permanent CleanBar Eye icon and the dedicated menu bar spacer item.
@MainActor
public final class MenuBarSpacerController: NSObject {
    public private(set) var controlItem: NSStatusItem?
    public private(set) var spacerItem: NSStatusItem?
    public private(set) var isExpanded: Bool = false
    public let floatingShelf = FloatingShelfController()
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
        setupStatusItems()
        if let obs = observer {
            floatingShelf.configure(observer: obs, onOpenPreferences: { [weak self] in
                self?.openPreferences()
            })
        }
    }

    public func configure(observer: StatusBarObserver, stateStore: StateStore) {
        self.observer = observer
        self.stateStore = stateStore
        floatingShelf.configure(observer: observer, onOpenPreferences: { [weak self] in
            self?.openPreferences()
        })
    }

    private func setupStatusItems() {
        // 1. Control Status Item (The permanent 24px Eye icon)
        let control = NSStatusBar.system.statusItem(withLength: 24.0)
        if let button = control.button {
            let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "CleanBar")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        control.length = 24.0
        self.controlItem = control

        // 2. Spacer Status Item (Invisible variable length spacer to the left of the Eye)
        let spacer = NSStatusBar.system.statusItem(withLength: 0.0)
        if let spacerButton = spacer.button {
            spacerButton.image = nil
            spacerButton.title = ""
            spacerButton.isTransparent = true
        }
        spacer.length = 0.0
        spacer.isVisible = false
        self.spacerItem = spacer
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

        controlItem?.menu = menu
        controlItem?.button?.performClick(nil)
        controlItem?.menu = nil
    }

    @objc public func openPreferences() {
        guard let observer = observer, let stateStore = stateStore, let button = controlItem?.button else { return }

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
        guard let stateStore = stateStore, let button = controlItem?.button else { return }

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

    /// Calculates safe collapse length based on the total width of items to the left, bounded by the Notch.
    public func calculateTargetSpacerLength() -> CGFloat {
        guard let button = controlItem?.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            return 80.0
        }

        let eyeRightX = window.frame.maxX
        var notchRightEdgeX: CGFloat = 400.0
        if #available(macOS 12.0, *) {
            if let topRightArea = screen.auxiliaryTopRightArea, topRightArea.width > 0 {
                notchRightEdgeX = topRightArea.origin.x
            } else if let topLeftArea = screen.auxiliaryTopLeftArea, topLeftArea.width > 0 {
                notchRightEdgeX = topLeftArea.maxX
            }
        }

        let distanceToNotch = max(30.0, eyeRightX - notchRightEdgeX - 10.0)

        if let obs = observer, obs.totalHiddenWidth > 10.0 {
            return min(obs.totalHiddenWidth + 10.0, distanceToNotch)
        }

        return min(80.0, distanceToNotch)
    }

    public func setExpanded(_ expanded: Bool, hiddenItemsCount: Int = 0) {
        if let button = controlItem?.button, let window = button.window {
            observer?.scanLeftHiddenItems(cleanBarEyeX: window.frame.minX)
        }

        guard self.isExpanded != expanded else { return }
        self.isExpanded = expanded

        // 1. Update Eye icon (always exactly 24px)
        let symbolName = expanded ? "eye.fill" : "eye.slash"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CleanBar")
        image?.isTemplate = true
        controlItem?.button?.image = image

        // 2. Update dedicated Spacer item
        let spacerLength = expanded ? 0.0 : calculateTargetSpacerLength()
        if expanded {
            spacerItem?.length = 0.0
            spacerItem?.isVisible = false
            floatingShelf.setVisible(true, relativeTo: controlItem?.button)
        } else {
            spacerItem?.length = spacerLength
            spacerItem?.isVisible = (spacerLength > 0)
            floatingShelf.setVisible(false, relativeTo: controlItem?.button)
        }
    }
}
