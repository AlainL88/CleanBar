import Cocoa
import ApplicationServices
import Combine

@MainActor
public final class StatusBarObserver: ObservableObject {
    @Published public private(set) var discoveredItems: [ItemConfig] = []
    @Published public private(set) var isAccessibilityTrusted: Bool = false
    @Published public private(set) var temporarilyRevealedItemIDs: Set<String> = []

    public var onItemsUpdated: (() -> Void)?
    private var revealTimers: [String: Timer] = [:]

    public let stateStore: StateStore
    private let workspaceNotificationCenter: NotificationCenter
    private let defaultNotificationCenter: NotificationCenter
    private let scanner: (() -> [String])?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultObservers: [NSObjectProtocol] = []

    public init(
        stateStore: StateStore,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        defaultNotificationCenter: NotificationCenter = .default,
        scanner: (() -> [String])? = nil
    ) {
        self.stateStore = stateStore
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.defaultNotificationCenter = defaultNotificationCenter
        self.scanner = scanner

        self.isAccessibilityTrusted = checkAccessibilityPermissions(prompt: false)
        setupNotificationObservers()
    }

    deinit {
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for observer in defaultObservers {
            defaultNotificationCenter.removeObserver(observer)
        }
        defaultObservers.removeAll()
    }

    @discardableResult
    public func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let trusted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        if Thread.isMainThread {
            self.isAccessibilityTrusted = trusted
        } else {
            DispatchQueue.main.async {
                self.isAccessibilityTrusted = trusted
            }
        }
        return trusted
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func triggerTemporaryReveal(for id: String, duration: TimeInterval = 5.0) {
        let updateBlock = {
            self.revealTimers[id]?.invalidate()
            self.temporarilyRevealedItemIDs.insert(id)

            let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.temporarilyRevealedItemIDs.remove(id)
                self.revealTimers.removeValue(forKey: id)
            }
            self.revealTimers[id] = timer
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    public func isTemporarilyRevealed(_ id: String) -> Bool {
        return temporarilyRevealedItemIDs.contains(id)
    }

    /// Triggers the status bar item or activates its parent application.
    public func triggerItem(id: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == id || $0.localizedName == id
        }) else { return }

        if isAccessibilityTrusted {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var extrasMenuBar: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasMenuBar) == .success,
               let extras = extrasMenuBar {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement],
                   let firstChild = children.first {
                    AXUIElementPerformAction(firstChild, kAXPressAction as CFString)
                    return
                }
            }
        }

        app.activate()
    }

    @discardableResult
    public func scanMenuBarItems() -> [String] {
        _ = checkAccessibilityPermissions(prompt: false)

        if let customScanner = scanner {
            let rawItemIDs = customScanner()
            let itemIDs = processItemIDs(rawItemIDs)
            let configs = itemIDs.map { ItemConfig(id: $0, category: self.stateStore.category(for: $0)) }
            if Thread.isMainThread {
                self.discoveredItems = configs
                self.onItemsUpdated?()
            } else {
                DispatchQueue.main.sync {
                    self.discoveredItems = configs
                    self.onItemsUpdated?()
                }
            }
            return itemIDs
        }

        // Run scan on background queue to keep UI responsive
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let rawItemIDs = self.performScan()
            let itemIDs = self.processItemIDs(rawItemIDs)
            let configs = itemIDs.map { ItemConfig(id: $0, category: self.stateStore.category(for: $0)) }

            DispatchQueue.main.async {
                self.discoveredItems = configs
                self.onItemsUpdated?()
            }
        }

        return discoveredItems.map(\.id)
    }

    private func processItemIDs(_ rawItemIDs: [String]) -> [String] {
        var seen = Set<String>()
        var itemIDs: [String] = []
        for id in rawItemIDs where !id.isEmpty {
            if !seen.contains(id) {
                seen.insert(id)
                itemIDs.append(id)
            }
        }
        return itemIDs
    }

    private func setupNotificationObservers() {
        let launchObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scanMenuBarItems()
        }
        workspaceObservers.append(launchObserver)

        let terminateObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scanMenuBarItems()
        }
        workspaceObservers.append(terminateObserver)

        let screenObserver = defaultNotificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scanMenuBarItems()
        }
        defaultObservers.append(screenObserver)
    }

    private func performScan() -> [String] {
        var itemIDs: [String] = []
        let selfBundleID = Bundle.main.bundleIdentifier

        // 1. Scan running background/accessory applications (which host menu bar icons)
        for runningApp in NSWorkspace.shared.runningApplications {
            let pid = runningApp.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if let bundleID = runningApp.bundleIdentifier, bundleID == selfBundleID { continue }

            if runningApp.activationPolicy == .accessory {
                if let id = runningApp.bundleIdentifier ?? runningApp.localizedName, !id.isEmpty {
                    if !itemIDs.contains(id) {
                        itemIDs.append(id)
                    }
                }
            }
        }

        // 2. Scan AX status items if accessibility permission is granted
        if isAccessibilityTrusted {
            for runningApp in NSWorkspace.shared.runningApplications {
                let pid = runningApp.processIdentifier
                guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
                let app = AXUIElementCreateApplication(pid)
                if hasStatusItem(app: app) {
                    if let id = resolveIdentifier(for: app, runningApp: runningApp), !itemIDs.contains(id) {
                        itemIDs.append(id)
                    }
                }
            }
        }

        return itemIDs
    }

    private func hasStatusItem(app: AXUIElement) -> Bool {
        var extrasMenuBar: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extrasMenuBar) == .success,
           extrasMenuBar != nil {
            return true
        }

        var statusItemRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, "AXStatusItem" as CFString, &statusItemRef) == .success,
           statusItemRef != nil {
            return true
        }

        return false
    }

    private func resolveIdentifier(for app: AXUIElement, runningApp: NSRunningApplication?) -> String? {
        if let bundleID = runningApp?.bundleIdentifier, !bundleID.isEmpty {
            return bundleID
        }

        if let localizedName = runningApp?.localizedName, !localizedName.isEmpty {
            return localizedName
        }

        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, "AXTitle" as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            return title
        }

        return nil
    }
}
