import XCTest
@testable import CleanBar

final class StatusBarObserverTests: XCTestCase {
    private var testUserDefaults: UserDefaults!
    private let suiteName = "com.barbar.tests.statusbarobserver"
    private var stateStore: StateStore!
    private var mockWorkspaceNC: NotificationCenter!
    private var mockDefaultNC: NotificationCenter!

    override func setUp() {
        super.setUp()
        testUserDefaults = UserDefaults(suiteName: suiteName)!
        testUserDefaults.removePersistentDomain(forName: suiteName)
        stateStore = StateStore(userDefaults: testUserDefaults)
        mockWorkspaceNC = NotificationCenter()
        mockDefaultNC = NotificationCenter()
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: suiteName)
        testUserDefaults = nil
        stateStore = nil
        mockWorkspaceNC = nil
        mockDefaultNC = nil
        super.tearDown()
    }

    func testDiscoveredItemsInitializesEmpty() {
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC
        )
        XCTAssertTrue(observer.discoveredItems.isEmpty)
    }

    func testScanMenuBarItemsWithCustomScannerUpdatesDiscoveredItems() {
        stateStore.setCategory(.hiddenOnHover, for: "com.apple.wifi")
        stateStore.setCategory(.deepHidden, for: "com.docker.docker")

        let mockIDs = ["com.apple.wifi", "com.apple.controlcenter", "com.docker.docker"]
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: { mockIDs }
        )

        let result = observer.scanMenuBarItems()

        XCTAssertEqual(result, mockIDs)
        XCTAssertEqual(observer.discoveredItems.count, 3)

        XCTAssertEqual(observer.discoveredItems[0].id, "com.apple.wifi")
        XCTAssertEqual(observer.discoveredItems[0].category, .hiddenOnHover)

        XCTAssertEqual(observer.discoveredItems[1].id, "com.apple.controlcenter")
        XCTAssertEqual(observer.discoveredItems[1].category, .hiddenOnHover)

        XCTAssertEqual(observer.discoveredItems[2].id, "com.docker.docker")
        XCTAssertEqual(observer.discoveredItems[2].category, .deepHidden)
    }

    func testFallbackToHiddenOnHoverForUnconfiguredItems() {
        let mockIDs = ["com.unknown.app"]
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: { mockIDs }
        )

        _ = observer.scanMenuBarItems()

        XCTAssertEqual(observer.discoveredItems.count, 1)
        XCTAssertEqual(observer.discoveredItems.first?.id, "com.unknown.app")
        XCTAssertEqual(observer.discoveredItems.first?.category, .hiddenOnHover)
    }

    func testDeduplicationOfScannedItems() {
        let mockIDs = ["com.apple.wifi", "com.apple.wifi", "com.google.Chrome", "com.apple.wifi"]
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: { mockIDs }
        )

        let result = observer.scanMenuBarItems()

        XCTAssertEqual(result, ["com.apple.wifi", "com.google.Chrome"])
        XCTAssertEqual(observer.discoveredItems.count, 2)
        XCTAssertEqual(observer.discoveredItems[0].id, "com.apple.wifi")
        XCTAssertEqual(observer.discoveredItems[1].id, "com.google.Chrome")
    }

    func testWorkspaceLaunchNotificationTriggersScan() {
        var currentMockIDs = ["com.apple.wifi"]
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: { currentMockIDs }
        )

        _ = observer.scanMenuBarItems()
        XCTAssertEqual(observer.discoveredItems.map(\.id), ["com.apple.wifi"])

        // Simulate app launch event
        currentMockIDs = ["com.apple.wifi", "com.1password.1password"]
        mockWorkspaceNC.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)

        XCTAssertEqual(observer.discoveredItems.map(\.id), ["com.apple.wifi", "com.1password.1password"])
    }

    func testWorkspaceTerminateNotificationTriggersScan() {
        var currentMockIDs = ["com.apple.wifi", "com.slack.Slack"]
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: { currentMockIDs }
        )

        _ = observer.scanMenuBarItems()
        XCTAssertEqual(observer.discoveredItems.count, 2)

        // Simulate app terminate event
        currentMockIDs = ["com.apple.wifi"]
        mockWorkspaceNC.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        XCTAssertEqual(observer.discoveredItems.map(\.id), ["com.apple.wifi"])
    }

    func testScreenParametersChangeNotificationTriggersScan() {
        var scanCount = 0
        let observer = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: {
                scanCount += 1
                return ["com.item"]
            }
        )

        XCTAssertEqual(scanCount, 0)
        mockDefaultNC.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(scanCount, 1)
        XCTAssertEqual(observer.discoveredItems.map(\.id), ["com.item"])
    }

    func testDeinitRemovesNotificationObservers() {
        var scanCount = 0
        var observer: StatusBarObserver? = StatusBarObserver(
            stateStore: stateStore,
            workspaceNotificationCenter: mockWorkspaceNC,
            defaultNotificationCenter: mockDefaultNC,
            scanner: {
                scanCount += 1
                return []
            }
        )
        _ = observer?.scanMenuBarItems()
        XCTAssertEqual(scanCount, 1)

        observer = nil

        mockWorkspaceNC.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        mockWorkspaceNC.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        mockDefaultNC.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // scanCount should not increase after observer is deallocated
        XCTAssertEqual(scanCount, 1)
    }

    func testDefaultAXScanExecution() {
        let observer = StatusBarObserver(stateStore: stateStore)
        let items = observer.scanMenuBarItems()
        // Default AX scan should return an array without throwing or crashing
        XCTAssertEqual(items.count, observer.discoveredItems.count)
    }
}
