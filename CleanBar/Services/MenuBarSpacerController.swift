import Cocoa
import SwiftUI

/// Single clean status item controller managing the permanent CleanBar Eye icon and the floating sub-bar shelf.
@MainActor
public final class MenuBarSpacerController: NSObject {
    public private(set) var statusItem: NSStatusItem?
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
        setupStatusItem()
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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .medium)
            let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "CleanBar")?.withSymbolConfiguration(symbolConfig)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            openPreferences()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(sender)
        } else {
            // Left click toggles the floating shelf
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

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
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

    public func setExpanded(_ expanded: Bool, hiddenItemsCount: Int = 0) {
        if let button = statusItem?.button, let window = button.window {
            observer?.scanLeftHiddenItems(cleanBarEyeX: window.frame.minX)
        }

        guard self.isExpanded != expanded else { return }
        self.isExpanded = expanded

        let symbolName = expanded ? "eye.fill" : "eye.slash"
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CleanBar")?.withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        statusItem?.button?.image = image

        if expanded {
            floatingShelf.setVisible(true, relativeTo: statusItem?.button)
        } else {
            floatingShelf.setVisible(false, relativeTo: statusItem?.button)
        }
    }
}
