import Cocoa
import ApplicationServices

/// `HoverMonitor` handles global mouse event monitoring and hover detection for
/// the CleanBar trigger (Eye icon) and the Floating Shelf panel.
///
/// Hover is **edge-triggered**: the shelf opens only when the cursor *enters*
/// the trigger or shelf region, and closes only when the cursor *leaves* both
/// regions (after a short grace period). A click that dismisses the shelf arms
/// a suppression state, so the still-hovering cursor does not immediately
/// reopen it. While a context menu is being tracked — or the user is
/// interacting with an item's menu — the shelf is held open regardless of the
/// cursor position.
@MainActor
public final class HoverMonitor {

    // MARK: - Public Properties

    /// Callback invoked when the hover state changes (debounced).
    public var onHoverChanged: ((Bool) -> Void)?

    /// Current hover status.
    public private(set) var isCurrentlyHovered: Bool = false

    /// Indicates whether global mouse tracking is active.
    public private(set) var isMonitoring: Bool = false

    /// Provider returning the current on-screen frame of the CleanBar trigger (Eye icon).
    public var triggerFrameProvider: (() -> CGRect?)?

    /// Provider returning the current screen frame of the floating shelf panel.
    public var floatingPanelFrameProvider: (() -> CGRect?)?

    /// Flag indicating whether the user is actively interacting with an item menu.
    public var isInteracting: Bool = false {
        didSet {
            if isInteracting {
                updateHoverState(true)
            }
        }
    }

    /// True while the cursor remains over the trigger/shelf after a click
    /// dismissed the shelf, so hover cannot immediately reopen it.
    public private(set) var isSuppressed: Bool = false

    /// Until this uptime, hover is prevented from closing the shelf after it was
    /// opened by a click (the Eye can shift as items reappear, so the cursor may
    /// briefly not be over it — give the user time to reach the shelf).
    private var stickyUntil: TimeInterval = 0

    // MARK: - Private Properties

    private var eventMonitor: Any?
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval
    private let unhoverDelay: TimeInterval
    private let menuBarHeight: CGFloat
    private let screenHeightProvider: () -> CGFloat
    private let appMenuChecker: (CGPoint) -> Bool
    private let eventMonitorFactory: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    private let eventMonitorRemover: (Any) -> Void
    private var isMenuTracking: Bool = false
    private var menuObservers: [NSObjectProtocol] = []
    /// Whether the cursor is currently inside the trigger or shelf region (edge-tracking state).
    private var wasOverRegions: Bool = false
    /// Last cursor position processed by `handleMouseMoved` (used for the post-menu re-check).
    private var lastMouseLocation: CGPoint?

    // MARK: - Initialization

    public init(
        debounceInterval: TimeInterval = 0.05,
        unhoverDelay: TimeInterval = 0.4,
        menuBarHeight: CGFloat = 32,
        screenHeightProvider: @escaping () -> CGFloat = { NSScreen.main?.frame.height ?? 1000 },
        appMenuChecker: @escaping (CGPoint) -> Bool = { _ in false },
        eventMonitorFactory: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any? = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        eventMonitorRemover: @escaping (Any) -> Void = { monitor in
            NSEvent.removeMonitor(monitor)
        }
    ) {
        self.debounceInterval = debounceInterval
        self.unhoverDelay = unhoverDelay
        self.menuBarHeight = menuBarHeight
        self.screenHeightProvider = screenHeightProvider
        self.appMenuChecker = appMenuChecker
        self.eventMonitorFactory = eventMonitorFactory
        self.eventMonitorRemover = eventMonitorRemover

        setupMenuObservers()
    }

    deinit {
        if let monitor = eventMonitor {
            eventMonitorRemover(monitor)
        }
        debounceTimer?.invalidate()
        for observer in menuObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupMenuObservers() {
        let beginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isMenuTracking = true
            // A real menu interaction overrides any click-dismissal suppression.
            self?.isSuppressed = false
            // The shelf is now held open; mark the "over regions" bookkeeping so a
            // later exit (even without a prior hover edge) is detected on menu end.
            self?.wasOverRegions = true
            self?.updateHoverState(true)
        }
        menuObservers.append(beginObserver)

        let endObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isMenuTracking = false
            // Keep grace period after menu closes. Use the last cursor position the
            // monitor actually processed (falling back to a live read), so the
            // re-check is deterministic and not dependent on a fresh global query.
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                let mouseLoc = self?.lastMouseLocation ?? NSEvent.mouseLocation
                self?.handleMouseMoved(mouseLoc)
            }
        }
        menuObservers.append(endObserver)
    }

    // MARK: - Monitoring Controls

    /// Starts global mouse movement monitoring.
    public func startMonitoring() {
        guard eventMonitor == nil else { return }
        isMonitoring = true
        eventMonitor = eventMonitorFactory([.mouseMoved]) { [weak self] event in
            let mouseLoc = NSEvent.mouseLocation
            self?.handleMouseMoved(mouseLoc)
        }
    }

    /// Stops global mouse movement monitoring.
    public func stopMonitoring() {
        if let monitor = eventMonitor {
            eventMonitorRemover(monitor)
            eventMonitor = nil
        }
        debounceTimer?.invalidate()
        debounceTimer = nil
        isMonitoring = false
        isSuppressed = false
        wasOverRegions = false
    }

    // MARK: - Hit-Testing

    /// Legacy utility: reports whether a point lies inside the top menu bar band.
    /// Kept for compatibility/tests; production hover detection is scoped to the
    /// CleanBar trigger frame (see `computeIsOverTrigger`).
    public func evaluateMousePosition(
        _ point: CGPoint,
        screenHeight: CGFloat,
        menuBarHeight: CGFloat = 32,
        isOverAppMenu: Bool = false
    ) -> Bool {
        let isTopInCocoa = point.y >= (screenHeight - menuBarHeight)
        let isTopInQuartz = point.y <= menuBarHeight && point.y >= 0

        let isInTopArea = isTopInCocoa || isTopInQuartz
        if !isInTopArea { return false }
        if isOverAppMenu { return false }
        return true
    }

    // MARK: - Mouse Handling

    public func handleMouseMoved(_ location: CGPoint) {
        lastMouseLocation = location
        let isOverTrigger = computeIsOverTrigger(location)
        let isOverShelf = computeIsOverShelf(location)
        let overRegions = isOverTrigger || isOverShelf

        // While a menu is tracked or the user is interacting with an item menu,
        // the shelf must stay open no matter where the cursor is. Deliberately do
        // NOT update `wasOverRegions` here: the pre-menu value must survive so a
        // later exit is still detected.
        if isMenuTracking || isInteracting {
            debounceTimer?.invalidate()
            debounceTimer = nil
            updateHoverState(true)
            return
        }

        // After a click closed the shelf, ignore the trigger while the cursor is
        // still over it so the shelf doesn't snap back open. Re-arm only once the
        // cursor leaves both regions.
        if isSuppressed {
            if overRegions {
                wasOverRegions = overRegions
                return
            }
            isSuppressed = false
        }

        if overRegions && !wasOverRegions {
            // Entered the trigger or shelf: open (edge-triggered, brief debounce).
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                self?.updateHoverState(true)
            }
        } else if !overRegions && wasOverRegions {
            if ProcessInfo.processInfo.systemUptime < stickyUntil {
                // Sticky post-click: hold the shelf open while the user reaches it.
                debounceTimer?.invalidate()
                debounceTimer = nil
            } else {
                // Left the trigger and the shelf: close after a short grace period.
                debounceTimer?.invalidate()
                debounceTimer = Timer.scheduledTimer(withTimeInterval: unhoverDelay, repeats: false) { [weak self] _ in
                    self?.updateHoverState(false)
                }
            }
        }
        wasOverRegions = overRegions
    }

    private func computeIsOverTrigger(_ location: CGPoint) -> Bool {
        if appMenuChecker(location) { return false }
        guard let frame = triggerFrameProvider?(), frame.width > 0, frame.height > 0 else { return false }
        // Generous margin so moving from the icon down to the shelf never flickers.
        return frame.insetBy(dx: -14, dy: -12).contains(location)
    }

    private func computeIsOverShelf(_ location: CGPoint) -> Bool {
        guard let shelfFrame = floatingPanelFrameProvider?(), shelfFrame.width > 0, shelfFrame.height > 0 else { return false }
        // Expand hit area slightly (8px) for effortless mouse transit.
        return shelfFrame.insetBy(dx: -8, dy: -8).contains(location)
    }

    // MARK: - Click Coordination

    /// Called after the shelf was opened by a click: marks the hover state as
    /// engaged so a subsequent mouse-exit closes the shelf normally. Hover-close is
    /// suppressed briefly so the user has time to reach the shelf even if the Eye
    /// shifts as the hidden items reappear.
    public func engageHover() {
        debounceTimer?.invalidate()
        stickyUntil = ProcessInfo.processInfo.systemUptime + 2.0
        isSuppressed = false
        wasOverRegions = true
        updateHoverState(true)
    }

    /// Called after a click dismissed the shelf: keeps it closed while the cursor
    /// remains over the trigger/shelf, re-arming hover once the cursor leaves.
    public func suppressHoverUntilLeave() {
        debounceTimer?.invalidate()
        wasOverRegions = true
        isSuppressed = true
        updateHoverState(false)
    }

    // MARK: - State Management

    private func updateHoverState(_ isHovered: Bool) {
        guard isCurrentlyHovered != isHovered else { return }
        isCurrentlyHovered = isHovered

        if Thread.isMainThread {
            onHoverChanged?(isHovered)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onHoverChanged?(isHovered)
            }
        }
    }
}
