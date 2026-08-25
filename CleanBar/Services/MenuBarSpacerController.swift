import Cocoa
import SwiftUI

/// Manages the permanent CleanBar Eye icon and the visual curtain overlay hiding left status bar items.
@MainActor
public final class MenuBarSpacerController: NSObject {
    public private(set) var controlItem: NSStatusItem?
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
        if let obs = observer {
            floatingShelf.configure(observer: obs, onOpenPreferences: { [weak self] in
                self?.openPreferences()
            })
        }
    }

    public func configure(
        observer: StatusBarObserver,
        stateStore: StateStore,
        onItemTriggered: (() -> Void)? = nil
    ) {
        self.observer = observer
        self.stateStore = stateStore
        floatingShelf.configure(
            observer: observer,
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onItemTriggered: onItemTriggered
        )
    }

    public func setupStatusItem() {
        guard controlItem == nil else { return }

        // Control Status Item (The 26px Eye icon)
        let item = NSStatusBar.system.statusItem(withLength: 26.0)
        if let button = item.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold)
            if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "CleanBar")?.withSymbolConfiguration(symbolConfig) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                button.image = img
            }
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "CleanBar - Clicca o passa il mouse per mostrare la barra fluttuante"
        }
        self.controlItem = item
    }

    /// Enforces hiding of all menu bar icons to the left of CleanBar on the main menu bar.
    public func enforceHiding() {
        guard let button = controlItem?.button, let window = button.window else { return }
        let eyeX = window.frame.minX
        SkyLightWindowManager.shared.hideItemsToTheLeft(of: eyeX)
        MenuBarCurtainController.shared.updateCurtain(eyeX: eyeX)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            openPreferences()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(sender)
        } else {
            toggleExpansion()
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
        SkyLightWindowManager.shared.showAllItems()
        MenuBarCurtainController.shared.hideCurtain()
        NSApp.terminate(nil)
    }

    @objc public func toggleExpansion() {
        setExpanded(!isExpanded)
        onToggle?(isExpanded)
    }

    public func setExpanded(_ expanded: Bool, hiddenItemsCount: Int = 0) {
        if let button = controlItem?.button, let window = button.window {
            observer?.scanLeftHiddenItems(cleanBarEyeX: window.frame.minX)
        }

        enforceHiding()

        guard self.isExpanded != expanded else { return }
        self.isExpanded = expanded

        let symbolName = expanded ? "eye.fill" : "eye.slash"
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CleanBar")?.withSymbolConfiguration(symbolConfig) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            controlItem?.button?.image = image
        }

        if expanded {
            floatingShelf.setVisible(true, relativeTo: controlItem?.button)
        } else {
            floatingShelf.setVisible(false, relativeTo: controlItem?.button)
        }
    }
}
