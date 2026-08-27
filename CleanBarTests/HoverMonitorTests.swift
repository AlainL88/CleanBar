import XCTest
@testable import CleanBar

@MainActor
final class HoverMonitorTests: XCTestCase {

    // MARK: - Test Constants

    /// Screen height used by every test.
    private let screenHeight: CGFloat = 1000

    /// Eye icon frame in the menu bar (Cocoa screen coordinates, bottom-left origin).
    private let eyeFrame = CGRect(x: 500, y: 968, width: 26, height: 32)

    /// Floating shelf frame right below the eye.
    private let shelfFrame = CGRect(x: 486, y: 924, width: 54, height: 40)

    private func makeMonitor(
        debounceInterval: TimeInterval = 0,
        unhoverDelay: TimeInterval = 0.05,
        withShelf: Bool = false
    ) -> HoverMonitor {
        let monitor = HoverMonitor(
            debounceInterval: debounceInterval,
            unhoverDelay: unhoverDelay,
            menuBarHeight: 30,
            screenHeightProvider: { self.screenHeight },
            appMenuChecker: { _ in false }
        )
        monitor.triggerFrameProvider = { self.eyeFrame }
        if withShelf {
            monitor.floatingPanelFrameProvider = { self.shelfFrame }
        }
        return monitor
    }

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

    // MARK: - Edge-Triggered Hover Tests

    func testImmediateHoverStateChangeWithZeroDebounce() {
        let expectationEntered = expectation(description: "Hover entered")
        let expectationExited = expectation(description: "Hover exited")

        var receivedStates: [Bool] = []

        let monitor = makeMonitor(debounceInterval: 0, unhoverDelay: 0.05)
        monitor.onHoverChanged = { isHovered in
            receivedStates.append(isHovered)
            if isHovered {
                expectationEntered.fulfill()
            } else {
                expectationExited.fulfill()
            }
        }

        // Move inside the eye trigger area
        monitor.handleMouseMoved(CGPoint(x: 513, y: 980))
        wait(for: [expectationEntered], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)

        // Redundant movement within the trigger should not fire another callback
        monitor.handleMouseMoved(CGPoint(x: 520, y: 985))
        XCTAssertEqual(receivedStates, [true])

        // Move outside the trigger and shelf areas
        monitor.handleMouseMoved(CGPoint(x: 500, y: 400))
        wait(for: [expectationExited], timeout: 1.0)
        XCTAssertFalse(monitor.isCurrentlyHovered)
        XCTAssertEqual(receivedStates, [true, false])
    }

    func testDebouncedHoverTransition() {
        let expectationHover = expectation(description: "Debounced hover entered")

        let monitor = makeMonitor(debounceInterval: 0.05)
        monitor.onHoverChanged = { isHovered in
            if isHovered {
                expectationHover.fulfill()
            }
        }

        // Move inside the eye trigger area
        monitor.handleMouseMoved(CGPoint(x: 513, y: 980))
        // Immediately, isCurrentlyHovered is still false until debounce fires
        XCTAssertFalse(monitor.isCurrentlyHovered)

        wait(for: [expectationHover], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)
    }

    func testHoverOnlyTriggersNearEyeIcon() {
        let expectationEntered = expectation(description: "Hover entered")

        let monitor = makeMonitor()
        monitor.onHoverChanged = { isHovered in
            if isHovered {
                expectationEntered.fulfill()
            }
        }

        // In the menu bar but far to the left (app menu area) → no hover.
        monitor.handleMouseMoved(CGPoint(x: 200, y: 980))
        XCTAssertFalse(monitor.isCurrentlyHovered)

        // In the menu bar far to the right of the eye → no hover.
        monitor.handleMouseMoved(CGPoint(x: 900, y: 985))
        XCTAssertFalse(monitor.isCurrentlyHovered)

        // On the eye itself → opens.
        monitor.handleMouseMoved(CGPoint(x: 513, y: 980))
        wait(for: [expectationEntered], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)
    }

    func testMovingFromEyeToShelfDoesNotClose() {
        let expectationEntered = expectation(description: "Hover entered")

        let monitor = makeMonitor(unhoverDelay: 0.4, withShelf: true)
        var didClose = false
        monitor.onHoverChanged = { isHovered in
            if isHovered {
                expectationEntered.fulfill()
            } else {
                didClose = true
            }
        }

        monitor.handleMouseMoved(CGPoint(x: 513, y: 980))
        wait(for: [expectationEntered], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)

        // Transit: move down from the eye into the shelf (through the expanded overlap).
        monitor.handleMouseMoved(CGPoint(x: 510, y: 940))
        XCTAssertTrue(monitor.isCurrentlyHovered)
        XCTAssertFalse(didClose)

        // Move within the shelf.
        monitor.handleMouseMoved(CGPoint(x: 505, y: 950))
        XCTAssertTrue(monitor.isCurrentlyHovered)
        XCTAssertFalse(didClose)
    }

    // MARK: - Click Dismissal & Suppression Tests

    func testClickDismissSuppressesReopenWhileCursorOverTrigger() {
        let expectationEntered = expectation(description: "Hover entered")
        let expectationReopen = expectation(description: "Reopen after leaving and re-entering")

        let monitor = makeMonitor()
        var hoverChanges: [Bool] = []
        monitor.onHoverChanged = { isHovered in
            hoverChanges.append(isHovered)
            if isHovered {
                expectationEntered.fulfill()
            }
        }

        // Hover the eye → shelf opens.
        monitor.handleMouseMoved(CGPoint(x: 513, y: 980))
        wait(for: [expectationEntered], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)

        // Click to dismiss (simulated) while the cursor is still over the eye.
        monitor.suppressHoverUntilLeave()
        XCTAssertFalse(monitor.isCurrentlyHovered)

        // Cursor stays over the eye; small movement must NOT reopen the shelf.
        monitor.handleMouseMoved(CGPoint(x: 520, y: 985))
        XCTAssertFalse(monitor.isCurrentlyHovered)
        XCTAssertEqual(hoverChanges, [true, false])

        // Cursor leaves the trigger area → suppression clears.
        monitor.handleMouseMoved(CGPoint(x: 300, y: 500))
        XCTAssertFalse(monitor.isCurrentlyHovered)

        // Moving back over the eye reopens the shelf.
        monitor.onHoverChanged = { isHovered in
            if isHovered {
                expectationReopen.fulfill()
            }
        }
        monitor.handleMouseMoved(CGPoint(x: 513, y: 980))
        wait(for: [expectationReopen], timeout: 1.0)
        XCTAssertTrue(monitor.isCurrentlyHovered)
    }

    // MARK: - Menu Tracking Persistence Tests

    func testMenuTrackingHoldsShelfOpenThenClosesAfterCursorAway() {
        let monitor = makeMonitor()
        monitor.onHoverChanged = { _ in }

        // Menu begins tracking while the cursor is away from the shelf/eye.
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: nil)
        XCTAssertTrue(monitor.isCurrentlyHovered)

        // Cursor moves far away: shelf must stay open during tracking.
        monitor.handleMouseMoved(CGPoint(x: 200, y: 500))
        XCTAssertTrue(monitor.isCurrentlyHovered)

        // Menu ends → after the grace check, the shelf closes because the cursor is away.
        let expectationClosed = expectation(description: "Closed after menu end")
        monitor.onHoverChanged = { isHovered in
            if !isHovered {
                expectationClosed.fulfill()
            }
        }
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: nil)
        wait(for: [expectationClosed], timeout: 3.0)
        XCTAssertFalse(monitor.isCurrentlyHovered)
    }
}
