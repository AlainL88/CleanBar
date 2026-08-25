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

        // Run AX scan asynchronously on background queue to keep UI 100% responsive
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let rawItemIDs = self.performAXScan()
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

    private func performAXScan() -> [String] {
        var itemIDs: [String] = []

        // System-wide AX Applications scan for status items
        let systemWide = AXUIElementCreateSystemWide()
        var appListRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, "AXApplications" as CFString, &appListRef) == .success,
           let apps = appListRef as? [AXUIElement] {
            for app in apps {
                var pid: pid_t = 0
                guard AXUIElementGetPid(app, &pid) == .success else { continue }
                let runningApp = NSRunningApplication(processIdentifier: pid)
                if hasStatusItem(app: app) {
                    if let id = resolveIdentifier(for: app, runningApp: runningApp) {
                        itemIDs.append(id)
                    }
                }
            }
        }

        // Running applications scan filtering strictly for apps with AXExtrasMenuBar status items
        let selfBundleID = Bundle.main.bundleIdentifier
        for runningApp in NSWorkspace.shared.runningApplications {
            let pid = runningApp.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if let bundleID = runningApp.bundleIdentifier, bundleID == selfBundleID { continue }

            let app = AXUIElementCreateApplication(pid)
            if hasStatusItem(app: app) {
                if let id = resolveIdentifier(for: app, runningApp: runningApp) {
                    itemIDs.append(id)
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

        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            return title
        }

        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            return desc
        }

        if let locName = runningApp?.localizedName, !locName.isEmpty {
            return locName
        }

        return nil
    }
}
