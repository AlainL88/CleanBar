import Cocoa
import SwiftUI

/// Manages the CleanBar Eye icon and the hiding of the left status bar items
/// using the Ice-style spacer technique.
///
/// A dedicated zero-width "spacer" status item (created with length 0 and its
/// layout slot constraint captured, exactly like Ice's ControlItem) sits between
/// the hidden items and the Eye. Growing it to a huge length pushes everything
/// to its LEFT off the screen (the hidden items), while the Eye and the visible
/// section to its right stay put. Shrinking it back brings the items home.
///
/// Because hiding is done by the system's own status-bar layout (no overlay),
/// the bar renders its natural frosted background — there is no curtain to go
/// stale or misalign, and nothing to match. Items that are off-screen are
/// clicked via a brief "temp-show" (Ice's tempShowItem): collapse the spacer,
/// let the item reappear at its real position, click it, re-collapse.
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
    private var appItemTriggered: (() -> Void)?
    private var tempShowTimer: Timer?
    private var tempShowUntil: Date = .distantPast
    /// Until this time, enforceHiding() is a no-op, so the items stay visible
    /// while the app's initial scan captures their real on-screen glyphs.
    private var suppressHideUntil: Date = .distantPast
    /// Periodically fixes items stuck between the Eye and the spacer (visible
    /// on the bar while the bar is hidden).
    private var stuckMonitor: Timer?
    private var isSweeping = false
    private var lastSweepAt: Date = .distantPast

    // Preferred positions, read from UserDefaults by the system on creation.
    private static let spacerAutosaveName = "CleanBar-Spacer"
    private static let eyeAutosaveName = "CleanBar-Eye"

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
        self.appItemTriggered = onItemTriggered
        floatingShelf.configure(
            observer: observer,
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onItemTriggered: { [weak self] item in
                guard let self else { return }
                // Notify the app layer (hover "interacting") so the shelf stays put
                // while the click completes.
                self.appItemTriggered?()
                // Temporarily show the items so the target sits at its real
                // on-screen position, click it there, then re-hide. AXPress alone
                // did not reliably open the menus.
                self.tempShowForClick(item) { item in
                    self.observer?.triggerStatusItem(item)
                }
            }
        )
    }

    public func setupStatusItem() {
        guard controlItem == nil else { return }

        // ---- Preferred positions (set BEFORE creating the items) ----
        // Empirically (this OS), a *higher* position value places the item
        // further LEFT of the Eye's slot. The spacer gets the higher value so it
        // sits just LEFT of the Eye: growing it to a huge length then pushes the
        // hidden items (further left) off-screen while the Eye stays put.
        let defaults = UserDefaults.standard
        // Seed the preferred positions only if absent. The spacer must sit at a
        // POSITIVE slot so that, at its resting (small) length, the hidden items
        // to its left are actually on-screen — that is what lets the initial scan
        // capture their real glyphs. A position of 2 resolves to ~x=1663; the Eye
        // at 0 sits just right of it (~x=1697).
        if defaults.object(forKey: "NSStatusItem Preferred Position \(Self.spacerAutosaveName)") == nil {
            defaults.set(2, forKey: "NSStatusItem Preferred Position \(Self.spacerAutosaveName)")
        }
        if defaults.object(forKey: "NSStatusItem Preferred Position \(Self.eyeAutosaveName)") == nil {
            defaults.set(0, forKey: "NSStatusItem Preferred Position \(Self.eyeAutosaveName)")
        }
        // The menu bar (hosted by Control Center on 26.5) reads the preferred
        // positions from the app's preferences. Without an explicit flush the
        // freshly-set values may not be visible yet and the Eye falls back to
        // the left edge of the bar.
        defaults.synchronize()

        // ---- Spacer item ----
        // A non-zero length so it participates in the normal status-bar layout
        // (a zero-length item gets pinned to the far right and ignores its
        // position). It renders as an invisible blank slot.
        let spacer = NSStatusBar.system.statusItem(withLength: 18.0)
        spacer.autosaveName = Self.spacerAutosaveName
        spacer.button?.title = ""
        self.spacerItem = spacer

        // ---- Control Status Item (the Eye) ----
        let item = NSStatusBar.system.statusItem(withLength: 26.0)
        item.autosaveName = Self.eyeAutosaveName
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

        // Keep the items visible through the initial icon-capture scan (the app
        // scans at ~3s while they are still on-screen), then hide. The scheduled
        // runs below are backstops; the capture scan's onItemsUpdated performs the
        // first real hide after suppressHideUntil passes.
        suppressHideUntil = Date().addingTimeInterval(4.5)
        for delay in [4.5, 6.0, 7.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.enforceHiding()
            }
        }
        // Watch for items that end up stuck between the Eye and the spacer
        // (visible on the bar while the bar is hidden) and push them left.
        // Start late so the post-hide scans have refreshed the cached frames.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.startStuckMonitor()
        }
    }

    /// Hides all status items located to the LEFT of the Eye by growing the
    /// spacer. Safe to call repeatedly. No-ops until the Eye has settled at a
    /// real position — hiding earlier pins the Eye to a degenerate frame — and
    /// until `suppressHideUntil` passes, so the initial scan can capture the
    /// items' real glyphs while they are still visible.
    public func enforceHiding() {
        if Date() < suppressHideUntil {
            return
        }
        guard let eye = eyeScreenFrame(), eye.minX > 100, eye.width > 10 else {
            NSLog("🪟 spacer: skip hide — eye non stabilita (\(eyeScreenFrame().map { NSStringFromRect($0) } ?? "nil"))")
            return
        }
        spacerItem?.length = 10_000
        NSLog("🪟 spacer: hidden (length 10000), eye frame=\(NSStringFromRect(eye))")
    }

    /// Returns the Eye's on-screen frame, or nil before it has settled.
    public func eyeScreenFrame() -> CGRect? {
        guard let button = controlItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.frame)
    }

    /// Removes the spacer status item entirely so the pushed-off hidden items
    /// reflow back to their natural on-screen positions. Used by the initial
    /// icon-capture flow — toggling the spacer's length does NOT bring them back
    /// once the system has persisted their pushed positions.
    public func removeSpacerForCapture() {
        if let spacer = spacerItem {
            NSStatusBar.system.removeStatusItem(spacer)
            spacerItem = nil
            NSLog("🪟 spacer: rimosso per cattura icone")
        }
    }

    /// Re-creates the spacer (same autosave name/position) and immediately hides
    /// the items again. Called after the icon-capture scan finishes.
    public func recreateSpacerAndHide() {
        suppressHideUntil = .distantPast
        guard spacerItem == nil else {
            enforceHiding()
            return
        }
        let spacer = NSStatusBar.system.statusItem(withLength: 18.0)
        spacer.autosaveName = Self.spacerAutosaveName
        spacer.button?.title = ""
        self.spacerItem = spacer
        NSLog("🪟 spacer: ricreato, nascondo")
        enforceHiding()
    }

    /// Temporarily shows the hidden items (collapses the spacer), so a target
    /// item can be clicked at its real on-screen position, then re-hides them
    /// after a grace period. Ice's tempShowItem, simplified to the whole section.
    public func tempShowForClick(_ item: StatusItemModel, clickHandler: @escaping (StatusItemModel) -> Void) {
        let wasHidden = (spacerItem?.length ?? 0) >= 1000
        guard wasHidden else {
            clickHandler(item)
            return
        }

        // Restore the spacer to its resting length: the hidden items pop back
        // onto the bar at their real positions.
        spacerItem?.length = 18
        tempShowTimer?.invalidate()
        tempShowTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.observer?.rearmFrames()
                clickHandler(item)
                self?.scheduleRehide(after: 4.0)
            }
        }
    }

    /// Re-hides the items after the given delay (in seconds). Does nothing if a
    /// temp-show is still needed.
    public func scheduleRehide(after seconds: TimeInterval = 0.0) {
        tempShowTimer?.invalidate()
        let fireDate = Date().addingTimeInterval(seconds)
        tempShowTimer = Timer.scheduledTimer(withTimeInterval: max(0, seconds), repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.enforceHiding()
            }
        }
        tempShowUntil = fireDate
    }

    /// True while the hidden items are temporarily visible on the bar.
    public var isTempShown: Bool {
        (spacerItem?.length ?? 0) < 1000
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
        let revealItem = NSMenuItem(title: "Mostra/Nascondi icone nascoste", action: #selector(toggleRevealHidden), keyEquivalent: "r")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(NSMenuItem.separator())

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

    /// Moves an item across the Eye so it becomes hidden (left) or visible (right),
    /// driven by the Settings toggle. Reveals the items, simulates a Cmd+drag, then
    /// re-hides.
    public func setItemHidden(_ item: StatusItemModel, hidden: Bool) {
        let wasHidden = (spacerItem?.length ?? 0) >= 1000
        spacerItem?.length = 18
        suppressHideUntil = .distantFuture
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.observer?.rearmFrames()
            guard let element = item.axElement,
                  let frame = self.observer?.currentFrame(of: element),
                  frame.minX >= 90, frame.width > 8,
                  let eye = self.eyeScreenFrame() else { return }
            let start = CGPoint(x: frame.midX, y: frame.midY)
            // Well to the LEFT of the Eye, so the system assigns a preferred
            // position higher than the spacer's — otherwise a drop just left of
            // the Eye lands between Eye and spacer and never gets pushed off.
            let dest = CGPoint(x: hidden ? eye.minX - 220 : eye.maxX + 24, y: frame.midY)
            NSLog("🪟 setItemHidden: \(item.id) hidden=\(hidden) start=\(start) dest=\(dest)")
            self.dragItem(from: start, to: dest)
            try? await Task.sleep(nanoseconds: 400_000_000)
            if wasHidden {
                self.suppressHideUntil = .distantPast
                self.enforceHiding()
            }
            // Settle, then sweep: re-scan and pull any item that ended up stuck
            // (still visible just left of the Eye) further left so it hides.
            self.sweepStuckItems()
        }
    }

    /// Simulates a Cmd+drag from one screen point to another (moving a menu bar item).
    private func dragItem(from start: CGPoint, to end: CGPoint) {
        CGDisplayHideCursor(CGMainDisplayID())
        defer { CGDisplayShowCursor(CGMainDisplayID()) }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(60_000)
        let steps = 12
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
            drag?.flags = .maskCommand
            drag?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    /// Temporarily shows the hidden items so the user can Cmd+drag them: move one
    /// to the right of the Eye to make it visible, or drag it off the bar to remove
    /// it. Toggling again re-hides them.
    @objc public func toggleRevealHidden() {
        let isHidden = (spacerItem?.length ?? 0) >= 1000
        if isHidden {
            spacerItem?.length = 18
            suppressHideUntil = .distantFuture  // keep them visible while managing
            NSLog("🪟 reveal: icone mostrate per gestione")
        } else {
            spacerItem?.length = 10_000
            suppressHideUntil = .distantPast
            NSLog("🪟 reveal: icone nascoste")
            sweepStuckItems()
        }
    }

    /// After hiding, an item dropped just LEFT of the Eye can land with a
    /// preferred position between the Eye and the spacer, so the grown spacer
    /// never pushes it off — it stays visible in the bar while the scan still
    /// adds it to the shelf. Any hidden item whose frame is still on-screen is
    /// stuck; drag it well to the left so the spacer finally pushes it off.
    private func sweepStuckItems() {
        guard !isSweeping else { return }
        isSweeping = true
        Task { @MainActor [weak self] in
            defer { self?.isSweeping = false }
            guard let self else { return }
            // Don't run while the user is managing items (reveal keeps them
            // visible on purpose) or during a temp-show.
            guard Date() >= suppressHideUntil else { return }
            guard (spacerItem?.length ?? 0) >= 1000 else { return }
            guard let eye = self.eyeScreenFrame() else { return }
            let eyeX = eye.minX
            self.observer?.scanLeftHiddenItems(cleanBarEyeX: eyeX)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let items = self.observer?.leftHiddenItems else { return }
            let stuck = items.filter { $0.frame.minX >= 90 }
            guard !stuck.isEmpty else { return }

            // A stuck item can sit ON TOP of the Eye (same preferred-position
            // range), so clicking its centre would hit the Eye and the drag
            // would do nothing. Reveal the whole section first: the item moves
            // back to its natural slot, becomes reachable, gets dragged well to
            // the left, then everything hides again.
            self.spacerItem?.length = 18
            self.suppressHideUntil = Date().addingTimeInterval(3.0)
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.observer?.rearmFrames()
            for item in stuck {
                guard let element = item.axElement,
                      let frame = self.observer?.currentFrame(of: element),
                      frame.minX >= 90 else { continue }
                let start = CGPoint(x: frame.midX, y: frame.midY)
                let dest = CGPoint(x: eyeX - 260, y: frame.midY)
                NSLog("🪟 sweep: \(item.id) a \(Int(frame.minX)) → sinistra")
                self.dragItem(from: start, to: dest)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            self.lastSweepAt = Date()
            self.suppressHideUntil = .distantPast
            self.spacerItem?.length = 10_000
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.enforceHiding()
            if let e = self.eyeScreenFrame()?.minX {
                self.observer?.scanLeftHiddenItems(cleanBarEyeX: e)
            }
        }
    }

    /// Periodic watchdog: while the bar is hidden, if any hidden item is still
    /// visible on-screen (stuck between Eye and spacer), sweep it left. This
    /// prevents the bug from persisting even when the reveal-time sweep missed it.
    private func startStuckMonitor() {
        stuckMonitor?.invalidate()
        stuckMonitor = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForStuckItems()
            }
        }
    }

    private func checkForStuckItems() {
        guard Date() >= suppressHideUntil,
              (spacerItem?.length ?? 0) >= 1000,
              Date().timeIntervalSince(lastSweepAt) > 3,
              !isSweeping else { return }
        guard let items = observer?.leftHiddenItems else { return }
        // Only trust items whose LIVE AX frame is on-screen (the cached frames
        // can be stale from a pre-hide scan).
        let stuck = items.filter { item in
            guard item.frame.minX >= 90 else { return false }
            guard let element = item.axElement,
                  let f = observer?.currentFrame(of: element) else { return false }
            return f.minX >= 90
        }
        if !stuck.isEmpty {
            NSLog("🪟 monitor: \(stuck.count) hidden item/i ancora visibili — sweep")
            sweepStuckItems()
        }
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
            },
            onSetItemHidden: { [weak self] item, hidden in
                self?.setItemHidden(item, hidden: hidden)
            }
        )

        popover.contentViewController = NSHostingController(rootView: settingsView)
        self.preferencesPopover = popover
        // Anchor at the centre of the Eye and force the popover below it, clamping
        // it fully inside the visible frame. A plain show(relativeTo:) can flip
        // above the menu bar on this OS and run off the top of the screen.
        let anchor = NSRect(x: button.bounds.midX, y: button.bounds.midY, width: 0, height: 0)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)
        if let screen = button.window?.screen ?? NSScreen.main,
           let popoverWindow = popover.contentViewController?.view.window {
            var f = popoverWindow.frame
            let vis = screen.visibleFrame
            let maxH = vis.maxY - vis.minY - 8
            if f.height > maxH { f.size.height = maxH }
            let eyeBottom = button.window?.convertToScreen(button.frame).minY ?? f.maxY
            f.origin.y = eyeBottom - f.height - 6
            if f.origin.y < vis.minY { f.origin.y = vis.minY }
            if f.origin.y + f.height > vis.maxY { f.origin.y = vis.maxY - f.height }
            if f.origin.x < vis.minX { f.origin.x = vis.minX }
            if f.origin.x + f.width > vis.maxX { f.origin.x = vis.maxX - f.width }
            popoverWindow.setFrame(f, display: true)
        }
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

    public func setExpanded(_ expanded: Bool, hiddenItemsCount: Int = 0) {
        // The spacer's hidden/shown state is managed by enforceHiding() /
        // tempShowForClick(), not by the shelf's open/closed state. Calling
        // enforceHiding() here would fight a temp-show in progress.

        guard self.isExpanded != expanded else {
            // Already in the target state — but refresh the panel geometry when
            // expanded, so a late-arriving item list repositions it correctly.
            if expanded {
                floatingShelf.setVisible(true, relativeTo: controlItem?.button)
            }
            return
        }

        // Refresh item frames only when the shelf is being opened (never on
        // collapse). This breaks the previous feedback loop
        // scan → onItemsUpdated → applyVisibility → scan.
        if expanded {
            if let eye = eyeScreenFrame() {
                observer?.scanLeftHiddenItems(cleanBarEyeX: eye.minX)
            }
        }

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
