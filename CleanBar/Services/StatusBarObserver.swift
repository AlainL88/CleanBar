import Cocoa
import ApplicationServices
import CoreGraphics
import Combine
import ScreenCaptureKit

@MainActor
public final class StatusBarObserver: ObservableObject {
    @Published public private(set) var discoveredItems: [ItemConfig] = []
    @Published public private(set) var leftHiddenItems: [StatusItemModel] = []
    /// User-defined shelf order (stable ids "bundle#idx", without the pid which
    /// changes across launches). Display order = manual order first, then any
    /// item not in it. Empty means "keep the natural bar order".
    @Published public private(set) var manualOrder: [String] = []
    @Published public private(set) var totalHiddenWidth: CGFloat = 120.0
    @Published public private(set) var isAccessibilityTrusted: Bool = false
    @Published public private(set) var temporarilyRevealedItemIDs: Set<String> = []

    public var onItemsUpdated: (() -> Void)?
    private var revealTimers: [String: Timer] = [:]
    private var permissionPollTimer: Timer?
    private var isScanning: Bool = false
    private var isScanningLeftItems: Bool = false
    /// Cached on-screen glyphs keyed by the stable item identity (`bundle#index`),
    /// so faithful icons survive the items being pushed off-screen by the spacer.
    /// Persisted to disk so a capture taken while the items were visible survives
    /// relaunches (the items are off-screen at startup, so a fresh capture would
    /// fall back to app icons).
    private var iconCache: [String: NSImage] = [:]
    private static let iconCacheDir: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("CleanBar/IconCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }()

    private func loadIconCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: Self.iconCacheDir) else { return }
        for file in files where file.hasSuffix(".png") {
            let id = String(file.dropLast(4))
            if let data = fm.contents(atPath: Self.iconCacheDir + "/" + file),
               let image = NSImage(data: data) {
                iconCache[id] = image
            }
        }
        // Load the persisted bar-order cache too.
        let orderURL = URL(fileURLWithPath: Self.iconCacheDir + "/orders.json")
        if let data = try? Data(contentsOf: orderURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
            itemOrderCache = json
        }
        // Load the persisted broken-AX id set (OneDrive stays next to the Eye).
        let brokenURL = URL(fileURLWithPath: Self.iconCacheDir + "/broken.json")
        if let data = try? Data(contentsOf: brokenURL),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            brokenAXIds = Set(arr)
        }
    }

    private func saveIconCache() {
        let fm = FileManager.default
        var saved = 0
        for (id, image) in iconCache {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let safeID = id.replacingOccurrences(of: "/", with: "_")
            let url = URL(fileURLWithPath: Self.iconCacheDir + "/" + safeID + ".png")
            do {
                try png.write(to: url)
                saved += 1
            } catch {
                NSLog("🪟 iconcache: errore salvataggio \(safeID): \(error)")
            }
        }
        // Persist the bar order so a hidden launch still sorts correctly.
        if let data = try? JSONSerialization.data(withJSONObject: itemOrderCache) {
            try? data.write(to: URL(fileURLWithPath: Self.iconCacheDir + "/orders.json"))
        }
        // Persist the broken-AX id set.
        if let data = try? JSONSerialization.data(withJSONObject: Array(brokenAXIds)) {
            try? data.write(to: URL(fileURLWithPath: Self.iconCacheDir + "/broken.json"))
        }
        NSLog("🪟 iconcache: salvate \(saved)/\(iconCache.count) in \(Self.iconCacheDir)")
    }
    /// Stable left-to-right bar order, captured from a scan in which the items were
    /// genuinely on-screen. Used so the floating shelf matches the bar's ordering
    /// even when the items are off-screen (their broken/negative AX frames would
    /// otherwise scramble the order — e.g. OneDrive is always reported at -4000).
    private var itemOrderCache: [String: Int] = [:]
    /// Item ids whose AX frame is broken (e.g. OneDrive always reports -4000).
    /// Persisted so a hidden scan doesn't forget to place them next to the Eye.
    private var brokenAXIds: Set<String> = []

    @MainActor private func cachedIcon(_ key: String) -> NSImage? { iconCache[key] }
    @MainActor private func setCachedIcon(_ image: NSImage, for key: String) { iconCache[key] = image }
    @MainActor private func setItemOrder(_ index: Int, for key: String) { itemOrderCache[key] = index }
    @MainActor private func itemOrder(for key: String) -> Int? { itemOrderCache[key] }
    @MainActor private func addBrokenAX(_ id: String) { brokenAXIds.insert(id) }
    @MainActor private func brokenAXContains(_ id: String) -> Bool { brokenAXIds.contains(id) }

    // MARK: - Manual shelf order

    private static let manualOrderKey = "CleanBarManualShelfOrder"

    /// Strips the pid out of "bundle#pid#idx", giving a stable "bundle#idx" key
    /// that survives relaunches (the pid changes every launch). Two processes of
    /// the same bundle both map to "bundle#0" — that is expected; the aligner in
    /// orderedForDisplay assigns one slot per running occurrence.
    private func stableID(_ id: String) -> String {
        let parts = id.split(separator: "#")
        if parts.count == 3 { return "\(parts[0])#\(parts[2])" }
        return id
    }

    /// The natural order as stable ids, one per running occurrence per bundle
    /// (OneDrive running two processes yields #0, #1 in bar order).
    @MainActor private func defaultOrder() -> [String] {
        var counts: [String: Int] = [:]
        return leftHiddenItems.map { item in
            let base = item.id.components(separatedBy: "#").first ?? item.id
            let idx = counts[base, default: 0]
            counts[base] = idx + 1
            return "\(base)#\(idx)"
        }
    }

    /// Display order: manual order first, then anything not in it (original
    /// order). Aligns each running item to the first unused manual slot of its
    /// bundle, so a multi-process app keeps its relative manual order across
    /// launches even though the pids change.
    @MainActor func orderedForDisplay(_ items: [StatusItemModel]) -> [StatusItemModel] {
        guard !manualOrder.isEmpty else { return items }
        var slotsByBundle: [String: [(String, Int)]] = [:]
        for (i, id) in manualOrder.enumerated() {
            let base = id.components(separatedBy: "#").first ?? id
            slotsByBundle[base, default: []].append((id, i))
        }
        var used = Set<String>()
        var runtimeToManual: [String: Int] = [:]
        for item in items {
            let base = item.id.components(separatedBy: "#").first ?? item.id
            guard let slots = slotsByBundle[base] else { continue }
            var assigned: Int?
            for (slotID, idx) in slots where !used.contains(slotID) {
                assigned = idx
                used.insert(slotID)
                break
            }
            if let a = assigned { runtimeToManual[item.id] = a }
        }
        let originalIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) }
        )
        return items.sorted { a, b in
            let ia = runtimeToManual[a.id], ib = runtimeToManual[b.id]
            switch (ia, ib) {
            case (nil, nil): return (originalIndex[a.id] ?? 0) < (originalIndex[b.id] ?? 0)
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?): return x < y
            }
        }
    }

    @MainActor public func setManualOrder(_ order: [String]) {
        manualOrder = order
        UserDefaults.standard.set(order, forKey: Self.manualOrderKey)
    }

    /// Move one item before another (drag reorder in Settings).
    @MainActor public func moveItem(id: String, before targetID: String) {
        let sid = stableID(id), starget = stableID(targetID)
        var ids = manualOrder
        if ids.isEmpty { ids = defaultOrder() }
        ids.removeAll { $0 == sid }
        if let idx = ids.firstIndex(of: starget) {
            ids.insert(sid, at: idx)
        } else {
            ids.append(sid)
        }
        setManualOrder(ids)
        leftHiddenItems = orderedForDisplay(leftHiddenItems)
    }

    /// Move one item to an absolute index (Cmd+drag on the shelf).
    @MainActor public func moveItem(id: String, toIndex: Int) {
        let sid = stableID(id)
        var ids = manualOrder
        if ids.isEmpty { ids = defaultOrder() }
        ids.removeAll { $0 == sid }
        let clamped = max(0, min(ids.count, toIndex))
        ids.insert(sid, at: clamped)
        setManualOrder(ids)
        leftHiddenItems = orderedForDisplay(leftHiddenItems)
    }

    /// Re-queries every hidden item's AX frame. Called right after a temp-show
    /// re-collapses the spacer, so items that reappeared on-screen report their
    /// real (positive) coordinates.
    public func rearmFrames() {
        let updated = leftHiddenItems.compactMap { item -> StatusItemModel? in
            guard let element = item.axElement, let rect = currentFrame(of: element),
                  rect.minX >= 0, rect.width > 8, rect.height > 8 else { return item }
            return StatusItemModel(
                id: item.id,
                appName: item.appName,
                frame: rect,
                iconImage: item.iconImage,
                axElement: element,
                subtitle: item.subtitle,
                isBrokenAX: item.isBrokenAX
            )
        }
        leftHiddenItems = updated
    }

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
        loadIconCache()
        self.manualOrder = UserDefaults.standard.stringArray(forKey: Self.manualOrderKey) ?? []
        setupNotificationObservers()
        startPermissionPolling()
    }

    deinit {
        permissionPollTimer?.invalidate()
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        for observer in defaultObservers {
            defaultNotificationCenter.removeObserver(observer)
        }
        defaultObservers.removeAll()
    }

    private func startPermissionPolling() {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let trusted = AXIsProcessTrusted()
                if self.isAccessibilityTrusted != trusted {
                    self.isAccessibilityTrusted = trusted
                    if trusted {
                        self.scanMenuBarItems()
                    }
                }
            }
        }
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

        self.isAccessibilityTrusted = trusted
        return trusted
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func triggerTemporaryReveal(for id: String, duration: TimeInterval = 5.0) {
        self.revealTimers[id]?.invalidate()
        self.temporarilyRevealedItemIDs.insert(id)

        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temporarilyRevealedItemIDs.remove(id)
                self.revealTimers.removeValue(forKey: id)
            }
        }
        self.revealTimers[id] = timer
    }

    public func isTemporarilyRevealed(_ id: String) -> Bool {
        return temporarilyRevealedItemIDs.contains(id)
    }

    /// Triggers a status item by injecting a native CGEvent click at its on-screen center coordinates.
    ///
    /// The click is delivered to the item's *current* position: the AX element is
    /// re-queried for fresh geometry before posting, so the cached frame snapshot
    /// being stale never makes the click miss the item.
    public func triggerStatusItem(_ item: StatusItemModel) {
        NSLog("🪟 triggerStatusItem: \(item.id) cachedFrame=\(item.frame)")
        // 1. Fresh geometry from the AX element (most reliable). The frame must be
        //    a real on-screen slot, clear of the Apple menu / app menu titles
        //    (x < 90): a stale or broken frame there would open the wrong menu.
        if let element = item.axElement, let rect = currentFrame(of: element),
           isClickable(frame: rect) {
            NSLog("🪟 triggerStatusItem: fresh AX frame=\(rect) → click at (\(rect.midX),\(rect.midY))")
            postClick(at: CGPoint(x: rect.midX, y: rect.midY))
            return
        }

        // 2. Cached frame snapshot as fallback (must be a valid on-screen position).
        if isClickable(frame: item.frame) {
            NSLog("🪟 triggerStatusItem: cached frame → click at (\(item.frame.midX),\(item.frame.midY))")
            postClick(at: CGPoint(x: item.frame.midX, y: item.frame.midY))
            return
        }

        // 3. Invalid/off-screen frame (some apps — e.g. OneDrive — report broken AX
        //    positions). NEVER post a click at a negative coordinate: it would land
        //    on the Apple/app menu. Try an Accessibility "press" on the element
        //    itself (menu bar items honour it regardless of position), then fall
        //    back to activating the app.
        NSLog("🪟 triggerStatusItem: frame non valido → tentativo AXPress")
        if let element = item.axElement,
           AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            NSLog("🪟 triggerStatusItem: AXPress riuscito")
            return
        }
        triggerItem(id: item.id)
    }

    /// Whether a frame is a safe on-screen click target. Guards against the
    /// Apple menu and app-menu title area (x < 90) and against degenerate frames.
    private func isClickable(frame: CGRect) -> Bool {
        guard frame.width > 8, frame.height > 8, frame.minX >= 90 else { return false }
        let screenW = NSScreen.main?.frame.width ?? 1920
        return frame.midX >= 90 && frame.midX <= screenW - 10
    }

    /// Returns the AX element's current on-screen frame (Quartz/global display coordinates).
    public func currentFrame(of element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posVal = posValue, let sizeVal = sizeValue else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    /// Posts a synthetic click at the given point. The cursor is hidden during the
    /// jump so the user doesn't see it teleport, and left at the item afterwards so
    /// the opened menu tracks it normally (Ice-style — warping back would dismiss
    /// the menu).
    private func postClick(at clickPoint: CGPoint) {
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            CGDisplayShowCursor(CGMainDisplayID())
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        usleep(40_000)
        mouseUp?.post(tap: .cghidEventTap)
    }

    /// Triggers the real status bar item via Accessibility press or a CGEvent click.
    /// The `id` may carry a `bundle#pid#index` suffix (as used by the hidden-items
    /// list); the index selects which of an app's several items to trigger.
    public func triggerItem(id: String) {
        let parts = id.split(separator: "#").map(String.init)
        let baseID = parts.first ?? id
        let index = Int(parts.last ?? "0") ?? 0
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == baseID || $0.localizedName == baseID
        }) else { return }

        if isAccessibilityTrusted {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var extrasMenuBar: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasMenuBar) == .success,
               let extras = extrasMenuBar {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement], !children.isEmpty {
                    let target = children[min(index, children.count - 1)]
                    // Prefer a direct press: position-independent and reliable even
                    // when the app reports a broken frame (e.g. OneDrive).
                    if AXUIElementPerformAction(target, kAXPressAction as CFString) == .success {
                        return
                    }
                    // Fall back to a synthetic click at the element's on-screen position.
                    var posValue: CFTypeRef?
                    var sizeValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &posValue) == .success,
                       AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &sizeValue) == .success,
                       let posVal = posValue, let sizeVal = sizeValue {
                        var point = CGPoint.zero
                        var size = CGSize.zero
                        if AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
                           AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
                           point.x >= 90, size.width > 8, size.height > 8 {
                            postClick(at: CGPoint(x: point.x + size.width / 2.0, y: point.y + size.height / 2.0))
                            return
                        }
                    }
                }
            }
        }

        app.activate()
    }

    /// Scans the system menu bar items located strictly to the LEFT of CleanBar's Eye icon.
    public func scanLeftHiddenItems(cleanBarEyeX: CGFloat = 0.0) {
        guard isAccessibilityTrusted, !isScanningLeftItems else { return }
        isScanningLeftItems = true

        let selfPID = ProcessInfo.processInfo.processIdentifier

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.performLeftScan(cleanBarEyeX: cleanBarEyeX, selfPID: selfPID)
        }
    }

    nonisolated private func performLeftScan(cleanBarEyeX: CGFloat, selfPID: pid_t) async {
        var items: [StatusItemModel] = []
        var eyeX = cleanBarEyeX

        if eyeX <= 0 {
            let selfApp = AXUIElementCreateApplication(selfPID)
            var extrasMenuBar: CFTypeRef?
            if AXUIElementCopyAttributeValue(selfApp, "AXExtrasMenuBar" as CFString, &extrasMenuBar) == .success,
               let extras = extrasMenuBar {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement], let firstChild = children.first {
                    var posValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(firstChild, kAXPositionAttribute as CFString, &posValue) == .success,
                       let posVal = posValue {
                        var point = CGPoint.zero
                        if AXValueGetValue(posVal as! AXValue, .cgPoint, &point) {
                            eyeX = point.x
                        }
                    }
                }
            }
        }

        if eyeX <= 0 {
            eyeX = 1200.0
        }

        let ignoredSystemPrefixes = [
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.Spotlight",
            "com.apple.Siri"
        ]

        let apps = NSWorkspace.shared.runningApplications
        let selfBundleID = Bundle.main.bundleIdentifier
        for runningApp in apps {
            let pid = runningApp.processIdentifier
            guard pid != selfPID else { continue }
            if let bundleID = runningApp.bundleIdentifier {
                // Never treat CleanBar's own items (a stray second instance can
                // appear with the same bundle id) as hidden items to show.
                if bundleID == selfBundleID { continue }
                if ignoredSystemPrefixes.contains(where: { bundleID.hasPrefix($0) }) { continue }
            }

            let appElement = AXUIElementCreateApplication(pid)
            var extrasMenuBar: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasMenuBar) == .success,
               let extras = extrasMenuBar {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    // Stable per-bundle index, so a hidden item's identity (and cached
                    // icon) survives its X position going negative when the spacer
                    // pushes it off-screen.
                    var bundleCounts: [String: Int] = [:]
                    for child in children {
                        var posValue: CFTypeRef?
                        var sizeValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posValue) == .success,
                           AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeValue) == .success,
                           let posVal = posValue, let sizeVal = sizeValue {
                            var point = CGPoint.zero
                            var size = CGSize.zero
                            if AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
                               AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
                               size.width > 8, size.height > 8 {
                                let rect = CGRect(origin: point, size: size)

                                if rect.midX < (eyeX + 10.0) {
                                    let appName = runningApp.localizedName ?? runningApp.bundleIdentifier ?? "Status Item"
                                    let baseID = runningApp.bundleIdentifier ?? appName
                                    let idx = bundleCounts[baseID] ?? 0
                                    bundleCounts[baseID] = idx + 1
                                    // An app can expose several items across several
                                    // processes (OneDrive runs two processes with the
                                    // same bundle id). Pin the pid into the identity so
                                    // the shelf never shows two colliding #0 tiles.
                                    let uniqueID = "\(baseID)#\(runningApp.processIdentifier)#\(idx)"
                                    // Prefer the item's real on-screen glyph. When the item
                                    // is genuinely on-screen, re-capture every scan (the bar
                                    // layout settles a moment after launch, so the first
                                    // captures can be of the wrong neighbours); when it is
                                    // off-screen (pushed away by the spacer) use the cache.
                                    let isOnScreen = rect.minX >= 90
                                    var icon = isOnScreen ? nil : await self.cachedIcon(uniqueID)
                                    if icon == nil {
                                        // Pelican's real menu bar glyph is a bare dot;
                                        // RealVNC's captured glyph is a spinner. Both
                                        // want a recognizable icon instead.
                                        let preferWeb = baseID == "com.smartalone.pelican"
                                        let preferBundle = baseID.hasPrefix("com.realvnc.")
                                        // 1. Real menu bar glyph (clean window capture).
                                        if let captured = await self.captureMenuIcon(for: rect),
                                           !preferWeb, !preferBundle, Self.hasSubstantialGlyph(captured) {
                                            icon = captured
                                        }
                                        // 2. App's official icon from the web (recognizable logo).
                                        if icon == nil, let web = await self.fetchWebIcon(bundleID: baseID) {
                                            icon = web
                                        }
                                        // 3. Whole-display composite crop (glyph + frosted bar).
                                        if icon == nil, !preferBundle,
                                           let composite = self.captureDisplayIcon(for: rect),
                                           Self.hasSubstantialGlyph(composite) {
                                            icon = composite
                                        }
                                        // 4. App's bundle icon (logo) or a scanned asset.
                                        if icon == nil, let resolved = await self.resolveMenuIcon(for: runningApp) {
                                            icon = resolved
                                        }
                                        if let icon { await self.setCachedIcon(icon, for: uniqueID) }
                                    }

                                    // AX title often carries the account (e.g.
                                    // "OneDrive — Personale\nBackup…"); keep the first
                                    // line for the shelf tooltip.
                                    var axTitle = ""
                                    var titleRef: CFTypeRef?
                                    if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
                                       let t = titleRef as? String {
                                        axTitle = t.components(separatedBy: "\n").first ?? t
                                    }
                                    NSLog("🪟 icon: \(uniqueID) onScreen=\(isOnScreen) frameX=\(Int(rect.minX)) icon=\(icon != nil) subtitle='\(axTitle)'")

                                    items.append(StatusItemModel(
                                        id: uniqueID,
                                        appName: appName,
                                        frame: rect,
                                        iconImage: icon,
                                        axElement: child,
                                        subtitle: axTitle
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }

        // Establish the stable bar order only from a scan where the items were
        // genuinely on-screen (a real Eye position was supplied and most frames are
        // valid). Once captured, it is reused for display regardless of the items
        // being off-screen later.
        // Window-list fallback: items whose AX frame is broken/off-screen even when
        // visible (OneDrive always reports -4000) can't be captured by frame. Find
        // the layer-25 windows left of the Eye that no valid item claims, and
        // capture those in bar order for the broken items.
        let brokenItems = items.filter { $0.frame.minX < 90 }
        if !brokenItems.isEmpty {
            let winInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            var hiddenWindows: [(UInt32, CGRect)] = []
            for w in winInfo {
                guard (w[kCGWindowLayer as String] as? Int) == 25 else { continue }
                let f = CGRect(dictionaryRepresentation: w[kCGWindowBounds as String] as! CFDictionary)!
                guard f.minX >= 0, f.minX < eyeX, f.width > 8 else { continue }
                hiddenWindows.append(((w[kCGWindowNumber as String] as! NSNumber).uint32Value, f))
            }
            let validMinXs = Set(items.filter { $0.frame.minX >= 90 }.map { Int($0.frame.minX) })
            let unmatched = hiddenWindows
                .filter { hw in !validMinXs.contains(where: { abs(Int(hw.1.minX) - $0) <= 4 }) }
                .sorted { $0.1.minX < $1.1.minX }

            for (i, item) in brokenItems.enumerated() where i < unmatched.count {
                // Never overwrite an icon the capture/web chain already provided
                // (e.g. OneDrive now gets its official web logo — a wrong window
                // glyph made it show purple/RealVNC before).
                guard item.iconImage == nil else { continue }
                if let glyph = await self.captureWindowGlyph(windowID: unmatched[i].0) {
                    if let idx = items.firstIndex(where: { $0.id == item.id }) {
                        items[idx] = StatusItemModel(
                            id: item.id, appName: item.appName, frame: item.frame,
                            iconImage: glyph, axElement: item.axElement,
                            subtitle: item.subtitle, isBrokenAX: item.isBrokenAX
                        )
                        await self.setCachedIcon(glyph, for: item.id)
                    }
                }
            }
        }

        // Mark items whose AX frame is broken (still off-screen while the others
        // are visible — e.g. OneDrive always reports -4000). They sit next to the
        // Eye on the bar, so the shelf must show them LAST.
        // Known apps whose AX frame is always broken (reports -4000) and that sit
        // next to the Eye on the bar — mark them broken on every scan.
        let knownBrokenPrefixes = ["com.microsoft.OneDrive-mac"]
        for i in items.indices {
            let isKnownBroken = knownBrokenPrefixes.contains { items[i].id.hasPrefix($0) }
            if isKnownBroken && !items[i].isBrokenAX {
                let it = items[i]
                await self.addBrokenAX(it.id)
                items[i] = StatusItemModel(
                    id: it.id, appName: it.appName, frame: it.frame,
                    iconImage: it.iconImage, axElement: it.axElement,
                    subtitle: it.subtitle, isBrokenAX: true
                )
            }
        }

        // Fallback: if a scan shows the items on-screen but some are still
        // off-screen, those are broken too (broken AX that we haven't seen yet).
        let realFrameCount = items.filter { $0.frame.minX >= 90 }.count
        if cleanBarEyeX > 100, realFrameCount >= items.count / 2 {
            for i in items.indices where items[i].frame.minX < 90 {
                let it = items[i]
                await self.addBrokenAX(it.id)
                items[i] = StatusItemModel(
                    id: it.id, appName: it.appName, frame: it.frame,
                    iconImage: it.iconImage, axElement: it.axElement,
                    subtitle: it.subtitle, isBrokenAX: true
                )
            }
        }

        // Shelf order = bar order: real items by their X position (AX minX, which
        // preserves left-to-right even when pushed negative), broken-AX items last.
        // Use the persisted set so a hidden scan still keeps OneDrive next to the Eye.
        var brokenSet: Set<String> = []
        for item in items {
            if await self.brokenAXContains(item.id) { brokenSet.insert(item.id) }
        }
        let sorted = items.sorted { a, b in
            let aBroken = a.isBrokenAX || brokenSet.contains(a.id)
            let bBroken = b.isBrokenAX || brokenSet.contains(b.id)
            if aBroken != bBroken { return !aBroken }
            return a.frame.minX < b.frame.minX
        }
        let totalW = sorted.reduce(0.0) { $0 + $1.frame.width }

        await MainActor.run {
            // Don't wipe a valid list if a transient scan finds nothing (e.g. the
            // bar is mid-reflow right after a drag) — keep the previous result.
            if !sorted.isEmpty {
                // Apply the user's manual shelf order on top of the bar order.
                self.leftHiddenItems = self.orderedForDisplay(sorted)
                if totalW > 0 {
                    self.totalHiddenWidth = totalW
                }
            }
            self.saveIconCache()
            self.isScanningLeftItems = false
            NSLog("🪟 scanLeftHiddenItems: found=%@",
                  sorted.map { "\($0.id)[\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width)),\(Int($0.frame.height))]" }.joined(separator: ", "))
            self.onItemsUpdated?()
        }
    }

    private func resolveMenuIcon(for runningApp: NSRunningApplication?) -> NSImage? {
        guard let app = runningApp else { return nil }

        // Prefer the app's main icon (a recognizable logo) over a guessed menu bar
        // asset — the bundle scan below can pick spinner/partial assets (RealVNC).
        if let icon = app.icon {
            return icon
        }

        if let bundleURL = app.bundleURL {
            let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
            if let enumerator = FileManager.default.enumerator(at: resourcesURL, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                    if (name.contains("status") || name.contains("menubar") || name.contains("tray") || name.contains("template") || name.contains("black") || name.contains("white"))
                        && (fileURL.pathExtension == "pdf" || fileURL.pathExtension == "png" || fileURL.pathExtension == "icns") {
                        if let image = NSImage(contentsOf: fileURL) {
                            image.isTemplate = true
                            return image
                        }
                    }
                }
            }
        }

        if let icon = app.icon {
            return icon
        }

        if let bundleURL = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return nil
    }

    /// Captures the item's actual on-screen glyph from its window content, so the
    /// floating shelf shows exactly what the user sees on the menu bar (not a
    /// guessed app icon). Uses ScreenCaptureKit; requires Screen Recording
    /// permission, otherwise falls back to nil.
    ///
    /// The item's frame is cropped out of the (possibly wider) hosting window, then
    /// trimmed to the opaque glyph and captured at 3x so the icon fills the shelf
    /// tile sharply instead of floating in transparent padding.
    nonisolated private func captureMenuIcon(for frame: CGRect) async -> NSImage? {
        guard frame.minX >= 90, frame.width >= 8, frame.height >= 8 else { return nil }
        // Per-window capture only (transparent background, exactly the glyph). The
        // display-composite fallback and the web/bundle lookups are handled by the
        // scan's fallback chain, since the composite always "succeeds" but includes
        // the frosted bar behind the glyph.
        return await captureWindowIcon(for: frame)
    }

    /// Captures a single item's host window via ScreenCaptureKit, trimming to the
    /// opaque glyph. Returns nil if the stream can't start (e.g. -3811).
    nonisolated private func captureWindowIcon(for frame: CGRect) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let candidates = content.windows.filter { $0.windowLayer == 25 && $0.frame.contains(center) }
            guard let window = candidates.min(by: {
                ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
            }) else { return nil }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(window.frame.width * 3)
            cfg.height = Int(window.frame.height * 3)
            cfg.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            guard let trimmed = Self.trimTransparent(in: image) else { return nil }
            let nsImage = NSImage(cgImage: trimmed, size: .zero)
            nsImage.isTemplate = Self.isMonochrome(in: trimmed)
            NSLog("🪟 capture[win]: frame=\(NSStringFromRect(frame)) trimmed=\(trimmed.width)x\(trimmed.height)")
            return nsImage
        } catch {
            NSLog("🪟 capture[win]: fallback composito (\(error))")
            return nil
        }
    }

    /// Whole-display composite capture (dlsym'd CGDisplayCreateImage), cropped to
    /// the item's frame. Includes the frosted bar behind the glyph.
    /// Fetches the app's official icon from the iTunes Search API (by bundle id),
    /// so a capture failure falls back to a recognizable, clean logo instead of a
    /// random asset from the app bundle. Returns nil if offline or not found.
    nonisolated private func fetchWebIcon(bundleID: String) async -> NSImage? {
        guard let lookup = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: lookup)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["results"] as? [[String: Any]]
            guard let artwork = results?.first?["artworkUrl512"] as? String,
                  let artURL = URL(string: artwork) else { return nil }
            let (imgData, _) = try await URLSession.shared.data(from: artURL)
            guard let image = NSImage(data: imgData) else { return nil }
            NSLog("🪟 webfetch: \(bundleID) → ok")
            return image
        } catch {
            return nil
        }
    }

    nonisolated private func captureDisplayIcon(for frame: CGRect) -> NSImage? {
        guard let image = Self.captureDisplay() else {
            NSLog("🪟 capture[disp]: display capture fallita")
            return nil
        }
        let scale = CGFloat(image.width) / (NSScreen.main?.frame.width ?? CGFloat(image.width))
        let cropRect = CGRect(
            x: frame.minX * scale,
            y: frame.minY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard cropRect.width >= 4, cropRect.height >= 4, let cropped = image.cropping(to: cropRect) else { return nil }
        guard let trimmed = Self.trimTransparent(in: cropped) else { return nil }
        let nsImage = NSImage(cgImage: trimmed, size: .zero)
        nsImage.isTemplate = Self.isMonochrome(in: trimmed)
        NSLog("🪟 capture[disp]: frame=\(NSStringFromRect(frame)) trimmed=\(trimmed.width)x\(trimmed.height)")
        return nsImage
    }

    /// Captures the main display (composite, like `screencapture`) via the
    /// dlsym'd `CGDisplayCreateImage`, which is deprecated but still functional.
    nonisolated private static func captureDisplay() -> CGImage? {
        typealias DisplayImageFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGDisplayCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: DisplayImageFn.self)
        return fn(CGMainDisplayID())?.takeRetainedValue()
    }

    /// Captures the glyph of a specific menu bar item window (identified by its
    /// CGWindowID), trimming to its opaque content. Used for items whose AX frame
    /// is broken (e.g. OneDrive always reports -4000) — their real window is
    /// located through the window list while the items are on-screen.
    nonisolated private func captureWindowGlyph(windowID: CGWindowID) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
            let scale: CGFloat = 3
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard let trimmed = Self.trimTransparent(in: image) else { return nil }
            let nsImage = NSImage(cgImage: trimmed, size: .zero)
            nsImage.isTemplate = Self.isMonochrome(in: trimmed)
            NSLog("🪟 captureWindow: id=\(windowID) img=\(image.width)x\(image.height) trimmed=\(trimmed.width)x\(trimmed.height)")
            return nsImage
        } catch {
            return nil
        }
    }

    /// Whether a captured glyph has enough opaque content to be meaningful. A
    /// near-empty capture (e.g. a bare dot, like Pelican's minimal menu bar icon)
    /// is treated as unusable and falls through to the web logo.
    nonisolated private static func hasSubstantialGlyph(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let w = cg.width, h = cg.height, bpr = cg.bytesPerRow
        guard w > 0, h > 0 else { return false }
        let aOff = (cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first || cg.alphaInfo == .noneSkipFirst) ? 0 : 3
        var opaque = 0
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                if ptr[y * bpr + x * 4 + aOff] > 8 { opaque += 1 }
            }
        }
        let sampled = max(1, (w / 2) * (h / 2))
        return opaque >= sampled / 6
    }

    /// Whether the captured glyph is effectively monochrome (a template icon). A
    /// colored icon (e.g. a rainbow or brand glyph) keeps its colors.
    nonisolated private static func isMonochrome(in image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return true }
        let bpr = image.bytesPerRow
        let bpp = max(4, image.bitsPerPixel / 8)
        let alphaOffset: Int
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            alphaOffset = 0
        default:
            alphaOffset = 3
        }
        var opaque = 0
        var colorful = 0
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let o = y * bpr + x * bpp
                guard ptr[o + alphaOffset] > 40 else { continue }
                opaque += 1
                let r = Int(ptr[o]), g = Int(ptr[o + 1]), b = Int(ptr[o + 2])
                if max(r, g, b) - min(r, g, b) > 24 { colorful += 1 }
            }
        }
        return opaque == 0 || colorful * 10 <= opaque
    }

    /// Crops a captured window image to its opaque content, removing transparent
    /// padding so the icon fills the tile instead of floating in space.
    nonisolated private static func trimTransparent(in image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return nil }

        let bpr = image.bytesPerRow
        let bpp = max(4, image.bitsPerPixel / 8)
        // Alpha channel position depends on the pixel layout.
        let alphaOffset: Int
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            alphaOffset = 0
        default:
            alphaOffset = 3
        }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let off = y * bpr + x * bpp
                if ptr[off + alphaOffset] > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    @discardableResult
    public func scanMenuBarItems() -> [String] {
        _ = checkAccessibilityPermissions(prompt: false)

        if let customScanner = scanner {
            let rawItemIDs = customScanner()
            let itemIDs = processItemIDs(rawItemIDs)
            let configs = itemIDs.map { ItemConfig(id: $0, category: self.stateStore.category(for: $0)) }
            self.discoveredItems = configs
            self.scanLeftHiddenItems()
            self.onItemsUpdated?()
            return itemIDs
        }

        guard !isScanning else { return discoveredItems.map(\.id) }
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let rawItemIDs = self.performScan()
            let itemIDs = self.processItemIDs(rawItemIDs)

            DispatchQueue.main.async {
                let configs = itemIDs.map { ItemConfig(id: $0, category: self.stateStore.category(for: $0)) }
                self.discoveredItems = configs
                self.isScanning = false
                self.scanLeftHiddenItems()
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

        let becomeActiveObserver = defaultNotificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccessibilityPermissions(prompt: false)
        }
        defaultObservers.append(becomeActiveObserver)
    }

    private func performScan() -> [String] {
        var itemIDs: [String] = []
        let selfBundleID = Bundle.main.bundleIdentifier

        let ignoredBundlePrefixes = [
            "com.apple.speech",
            "com.apple.corespeechd",
            "com.apple.bird",
            "com.apple.cloudd",
            "com.apple.WebKit",
            "com.apple.telephonyutilities",
            "com.apple.CallHistory",
            "com.apple.CoreLocation",
            "com.apple.mediaremoteagent",
            "com.apple.audio",
            "com.apple.quicklook"
        ]

        if isAccessibilityTrusted {
            for runningApp in NSWorkspace.shared.runningApplications {
                let pid = runningApp.processIdentifier
                guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
                if let bundleID = runningApp.bundleIdentifier {
                    if bundleID == selfBundleID { continue }
                    if ignoredBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) { continue }
                }

                let app = AXUIElementCreateApplication(pid)
                if hasStatusItem(app: app) {
                    if let id = resolveIdentifier(for: app, runningApp: runningApp), !itemIDs.contains(id) {
                        itemIDs.append(id)
                    }
                }
            }
        }

        for runningApp in NSWorkspace.shared.runningApplications {
            let pid = runningApp.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if let bundleID = runningApp.bundleIdentifier {
                if bundleID == selfBundleID { continue }
                if ignoredBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) { continue }
            }

            if runningApp.activationPolicy == .accessory && runningApp.icon != nil {
                if let bundleID = runningApp.bundleIdentifier, !bundleID.hasPrefix("com.apple.") {
                    let id = bundleID
                    if !itemIDs.contains(id) {
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
