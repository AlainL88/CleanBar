import Cocoa
import ApplicationServices

/// `HoverMonitor` handles global mouse event monitoring and menu bar hit-testing.
/// It detects when the cursor is over the CleanBar trigger area or the Floating Shelf panel,
/// and prevents dismissal while interacting with context menus or hovering over the sub-bar.
@MainActor
public final class HoverMonitor {

    // MARK: - Public Properties

    /// Callback invoked when the hover state changes (debounced).
    public var onHoverChanged: ((Bool) -> Void)?

    /// Current hover status.
    public private(set) var isCurrentlyHovered: Bool = false

    /// Indicates whether global mouse tracking is active.
    public private(set) var isMonitoring: Bool = false

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
            self?.updateHoverState(true)
        }
        menuObservers.append(beginObserver)

        let endObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isMenuTracking = false
            // Keep grace period after menu closes
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                let mouseLoc = NSEvent.mouseLocation
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
    }

    // MARK: - Hit-Testing & Mouse Handling

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

    public func handleMouseMoved(_ location: CGPoint) {
        let screenHeight = screenHeightProvider()
        let isOverMenu = appMenuChecker(location)

        // 1. Is mouse in top menu bar trigger area?
        let isOverMenuBar = evaluateMousePosition(
            location,
            screenHeight: screenHeight,
            menuBarHeight: menuBarHeight,
            isOverAppMenu: isOverMenu
        )

        // 2. Is mouse inside or hovering over the Floating Shelf panel?
        var isOverShelf = false
        if let shelfFrame = floatingPanelFrameProvider?(), shelfFrame.width > 0, shelfFrame.height > 0 {
            // Expand hit area slightly (8px) for effortless mouse transit
            let expandedFrame = shelfFrame.insetBy(dx: -8, dy: -8)
            if expandedFrame.contains(location) {
                isOverShelf = true
            }
        }

        // 3. Combined effective hover condition
        let shouldBeHovered = isOverMenuBar || isOverShelf || isMenuTracking || isInteracting

        if isMenuTracking || isInteracting {
            updateHoverState(true)
            return
        }

        debounceTimer?.invalidate()
        let delay = shouldBeHovered ? debounceInterval : unhoverDelay
        if delay <= 0 {
            updateHoverState(shouldBeHovered)
        } else {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.updateHoverState(shouldBeHovered)
            }
        }
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
