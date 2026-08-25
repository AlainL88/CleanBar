import Cocoa
import ApplicationServices

/// `HoverMonitor` handles global mouse event monitoring and menu bar hit-testing.
/// It detects when the cursor enters empty space or status item regions in the menu bar,
/// while suppressing activations when hovering over active application menus.
@MainActor
public final class HoverMonitor {

    // MARK: - Public Properties

    /// Callback invoked when the hover state changes (debounced by default).
    public var onHoverChanged: ((Bool) -> Void)?

    /// Current hover status indicating whether the cursor is over empty menu bar space.
    public private(set) var isCurrentlyHovered: Bool = false

    /// Indicates whether global mouse tracking is active.
    public private(set) var isMonitoring: Bool = false

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

    /// Initializes a `HoverMonitor` instance with configurable dependencies.
    public init(
        debounceInterval: TimeInterval = 0.05,
        unhoverDelay: TimeInterval = 0.5,
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
        }
        menuObservers.append(endObserver)
    }

    // MARK: - Monitoring Controls

    /// Starts global mouse movement monitoring.
    public func startMonitoring() {
        guard eventMonitor == nil else { return }
        isMonitoring = true
        eventMonitor = eventMonitorFactory([.mouseMoved]) { [weak self] event in
            // Use NSEvent.mouseLocation for true Cocoa screen coordinates
            let mouseLoc = NSEvent.mouseLocation
            self?.handleMouseMoved(mouseLoc)
        }
    }

    /// Stops global mouse movement monitoring and invalidates active debounce timers.
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
        // Handle both Cocoa (bottom-left origin) and Quartz (top-left origin) coordinates
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
        let isHovered = evaluateMousePosition(
            location,
            screenHeight: screenHeight,
            menuBarHeight: menuBarHeight,
            isOverAppMenu: isOverMenu
        )

        if isMenuTracking {
            updateHoverState(true)
            return
        }

        debounceTimer?.invalidate()
        let delay = isHovered ? debounceInterval : unhoverDelay
        if delay <= 0 {
            updateHoverState(isHovered)
        } else {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.updateHoverState(isHovered)
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
