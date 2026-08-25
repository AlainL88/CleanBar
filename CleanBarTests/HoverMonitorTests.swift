import XCTest
@testable import CleanBar

@MainActor
final class HoverMonitorTests: XCTestCase {

    // MARK: - Hit-Testing Logic Tests

    func testPointOutsideTopMenuBarReturnsFalse() {
        let monitor = HoverMonitor()
        let lowPoint = CGPoint(x: 500, y: 100) // Screen height ~1000
        XCTAssertFalse(monitor.evaluateMousePosition(lowPoint, screenHeight: 1000, menuBarHeight: 30))
    }

    func testPointInTopMenuBarReturnsTrueForEmptySpace() {
        let monitor = HoverMonitor()
        let topPoint = CGPoint(x: 500, y: 985)
        XCTAssertTrue(monitor.evaluateMousePosition(topPoint, screenHeight: 1000, menuBarHeight: 30, isOverAppMenu: false))
    }

    func testPointOverAppMenuReturnsFalse() {
        let monitor = HoverMonitor()
        let topPoint = CGPoint(x: 100, y: 985) // Over 'File' menu
        XCTAssertFalse(monitor.evaluateMousePosition(topPoint, screenHeight: 1000, menuBarHeight: 30, isOverAppMenu: true))
    }

    func testBoundaryConditionExactMenuBarHeight() {
        let monitor = HoverMonitor()
        let exactBoundaryPoint = CGPoint(x: 500, y: 970) // 1000 - 30 = 970
        XCTAssertTrue(monitor.evaluateMousePosition(exactBoundaryPoint, screenHeight: 1000, menuBarHeight: 30, isOverAppMenu: false))

        let justBelowPoint = CGPoint(x: 500, y: 969.9)
        XCTAssertFalse(monitor.evaluateMousePosition(justBelowPoint, screenHeight: 1000, menuBarHeight: 30, isOverAppMenu: false))

        let topEdgePoint = CGPoint(x: 500, y: 1000)
        XCTAssertTrue(monitor.evaluateMousePosition(topEdgePoint, screenHeight: 1000, menuBarHeight: 30, isOverAppMenu: false))
    }

    func testDefaultParametersInEvaluateMousePosition() {
        let monitor = HoverMonitor()
        let topPoint = CGPoint(x: 500, y: 980)
        XCTAssertTrue(monitor.evaluateMousePosition(topPoint, screenHeight: 1000))

        let bottomPoint = CGPoint(x: 500, y: 500)
        XCTAssertFalse(monitor.evaluateMousePosition(bottomPoint, screenHeight: 1000))
    }

    // MARK: - Lifecycle & Monitoring Tests

    func testStartAndStopMonitoringLifecycle() {
        var addedMask: NSEvent.EventTypeMask?
        var removedMonitor: Any?
        let mockToken = "MockEventMonitorToken" as NSString

        let monitor = HoverMonitor(
            eventMonitorFactory: { mask, _ in
                addedMask = mask
                return mockToken
            },
            eventMonitorRemover: { token in
                removedMonitor = token
            }
        )

        XCTAssertFalse(monitor.isMonitoring)

        monitor.startMonitoring()
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertEqual(addedMask, [.mouseMoved])

        // Multiple calls should be idempotent
        monitor.startMonitoring()
        XCTAssertTrue(monitor.isMonitoring)

        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(removedMonitor as? NSString, mockToken)

        // Multiple stop calls should be safe
        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isMonitoring)
    }

    // MARK: - Debouncing & Hover State Transition Tests

    func testImmediateHoverStateChangeWithZeroDebounce() {
        let expectationEntered = expectation(description: "Hover entered")
        let expectationExited = expectation(description: "Hover exited")

        var receivedStates: [Bool] = []

        let monitor = HoverMonitor(
            debounceInterval: 0,
            menuBarHeight: 30,
            screenHeightProvider: { 1000 },
            appMenuChecker: { _ in false }
        )

        monitor.onHoverChanged = { isHovered in
            receivedStates.append(isHovered)
            if isHovered {
                expectationEntered.fulfill()
            } else {
                expectationExited.fulfill()
            }
        }

        // Move inside menu bar
        monitor.handleMouseMoved(CGPoint(x: 500, y: 985))
        wait(for: [expectationEntered], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)

        // Redundant movement within menu bar should not fire another callback
        monitor.handleMouseMoved(CGPoint(x: 520, y: 980))
        XCTAssertEqual(receivedStates, [true])

        // Move outside menu bar
        monitor.handleMouseMoved(CGPoint(x: 500, y: 400))
        wait(for: [expectationExited], timeout: 1.0)
        XCTAssertFalse(monitor.isCurrentlyHovered)
        XCTAssertEqual(receivedStates, [true, false])
    }

    func testDebouncedHoverTransition() {
        let expectationHover = expectation(description: "Debounced hover entered")

        let monitor = HoverMonitor(
            debounceInterval: 0.05,
            menuBarHeight: 30,
            screenHeightProvider: { 1000 },
            appMenuChecker: { _ in false }
        )

        monitor.onHoverChanged = { isHovered in
            if isHovered {
                expectationHover.fulfill()
            }
        }

        // Move inside menu bar
        monitor.handleMouseMoved(CGPoint(x: 500, y: 985))
        // Immediately, isCurrentlyHovered is still false until debounce fires
        XCTAssertFalse(monitor.isCurrentlyHovered)

        wait(for: [expectationHover], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)
    }

    func testAppMenuCheckerSuppressesHover() {
        var hoverChanges: [Bool] = []

        let monitor = HoverMonitor(
            debounceInterval: 0,
            menuBarHeight: 30,
            screenHeightProvider: { 1000 },
            appMenuChecker: { point in
                // Pretend x < 300 is over app menu titles (File, Edit, etc.)
                return point.x < 300
            }
        )

        monitor.onHoverChanged = { isHovered in
            hoverChanges.append(isHovered)
        }

        // Move into menu bar area, but over app menu
        monitor.handleMouseMoved(CGPoint(x: 150, y: 985))
        XCTAssertFalse(monitor.isCurrentlyHovered)
        XCTAssertTrue(hoverChanges.isEmpty)

        // Move into empty space / status item area (x = 600)
        monitor.handleMouseMoved(CGPoint(x: 600, y: 985))
        XCTAssertTrue(monitor.isCurrentlyHovered)
        XCTAssertEqual(hoverChanges, [true])
    }

    func testDeinitCleansUpEventMonitor() {
        var removed = false
        let token = "Token" as NSString

        do {
            let monitor = HoverMonitor(
                eventMonitorFactory: { _, _ in token },
                eventMonitorRemover: { _ in removed = true }
            )
            monitor.startMonitoring()
            XCTAssertFalse(removed)
        }

        XCTAssertTrue(removed)
    }
}
