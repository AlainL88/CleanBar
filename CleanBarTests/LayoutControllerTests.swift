import XCTest
import Cocoa
@testable import CleanBar

final class LayoutControllerTests: XCTestCase {
    var controller: LayoutController!

    override func setUp() {
        super.setUp()
        controller = LayoutController()
    }

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    // MARK: - Notch Collision & Jump Tests

    func testNextXPositionWithoutNotch() {
        let nextX = controller.nextXPosition(currentX: 100, itemWidth: 30, notchRect: nil)
        XCTAssertEqual(nextX, 130)

        let zeroNotch = CGRect(x: 500, y: 0, width: 0, height: 30)
        let nextXZero = controller.nextXPosition(currentX: 100, itemWidth: 30, notchRect: zeroNotch)
        XCTAssertEqual(nextXZero, 130)
    }

    func testNextXPositionWithNotchNoCollision() {
        let notchRect = CGRect(x: 600, y: 0, width: 200, height: 30)

        // Item well before notch (ends at 550 < 600)
        let beforeX = controller.nextXPosition(currentX: 500, itemWidth: 50, notchRect: notchRect)
        XCTAssertEqual(beforeX, 550)

        // Item well after notch (starts at 800 >= 800)
        let afterX = controller.nextXPosition(currentX: 800, itemWidth: 20, notchRect: notchRect)
        XCTAssertEqual(afterX, 820)
    }

    func testNextXPositionWithNotchCollision() {
        let notchRect = CGRect(x: 600, y: 0, width: 200, height: 30)

        // Case 1: Item starts before notch but ends inside notch (590 + 20 = 610 >= 600)
        let jumpFromBefore = controller.nextXPosition(currentX: 590, itemWidth: 20, notchRect: notchRect)
        XCTAssertEqual(jumpFromBefore, 800, "Should jump past notch.maxX when item extends into notch")

        // Case 2: Item starts exactly at notch.minX (600)
        let jumpFromStart = controller.nextXPosition(currentX: 600, itemWidth: 20, notchRect: notchRect)
        XCTAssertEqual(jumpFromStart, 800, "Should jump past notch.maxX when item starts at notch start")

        // Case 3: Item starts inside notch (610)
        let jumpFromInside = controller.nextXPosition(currentX: 610, itemWidth: 20, notchRect: notchRect)
        XCTAssertGreaterThanOrEqual(jumpFromInside, 800, "Should jump past notch.maxX when item starts inside notch")

        // Case 4: Item starts before notch and spans across entire notch (550 + 300 = 850)
        let jumpSpanAcross = controller.nextXPosition(currentX: 550, itemWidth: 300, notchRect: notchRect)
        XCTAssertEqual(jumpSpanAcross, 800, "Should jump past notch.maxX when item spans across notch")
    }

    // MARK: - Compute Notch Rect Tests

    func testComputeNotchRectFromAuxiliaryAreas() {
        let topLeft = CGRect(x: 0, y: 970, width: 600, height: 30)
        let topRight = CGRect(x: 800, y: 970, width: 600, height: 30)
        let notch = controller.computeNotchRect(topLeft: topLeft, topRight: topRight, screenHeight: 1000)

        XCTAssertNotNil(notch)
        XCTAssertEqual(notch?.minX, 600)
        XCTAssertEqual(notch?.maxX, 800)
        XCTAssertEqual(notch?.width, 200)
        XCTAssertEqual(notch?.height, 30)
        XCTAssertEqual(notch?.origin.y, 970)
    }

    func testComputeNotchRectNilWhenNoNotch() {
        // Missing top-left
        let noTopLeft = controller.computeNotchRect(topLeft: nil, topRight: CGRect(x: 800, y: 0, width: 200, height: 30), screenHeight: 1000)
        XCTAssertNil(noTopLeft)

        // Missing top-right
        let noTopRight = controller.computeNotchRect(topLeft: CGRect(x: 0, y: 0, width: 600, height: 30), topRight: nil, screenHeight: 1000)
        XCTAssertNil(noTopRight)

        // Overlapping or invalid areas (no gap between left and right)
        let adjacent = controller.computeNotchRect(
            topLeft: CGRect(x: 0, y: 0, width: 800, height: 30),
            topRight: CGRect(x: 800, y: 0, width: 800, height: 30),
            screenHeight: 1000
        )
        XCTAssertNil(adjacent, "Adjacent areas with 0 gap should return nil")
    }

    // MARK: - Spacing & Padding Tests

    func testSpacingConstantsAndModes() {
        XCTAssertEqual(LayoutController.standardPadding, 16.0)
        XCTAssertEqual(LayoutController.compactPadding, 8.0)

        XCTAssertEqual(controller.padding(for: .standard), 16.0)
        XCTAssertEqual(controller.padding(for: .compact), 8.0)
        XCTAssertEqual(controller.padding(for: .custom(12.0)), 12.0)
    }

    func testResolveSpacingForExpandedAndCollapsedStates() {
        // Collapsed / not expanded always returns standard padding
        let collapsedPadding = controller.resolveSpacing(isExpanded: false, totalItemsWidth: 500, availableWidth: 400)
        XCTAssertEqual(collapsedPadding, LayoutController.standardPadding)

        // Expanded with ample available space returns standard padding
        let amplePadding = controller.resolveSpacing(isExpanded: true, totalItemsWidth: 300, availableWidth: 600)
        XCTAssertEqual(amplePadding, LayoutController.standardPadding)

        // Expanded with tight available space returns compact padding
        let tightPadding = controller.resolveSpacing(isExpanded: true, totalItemsWidth: 550, availableWidth: 500)
        XCTAssertEqual(tightPadding, LayoutController.compactPadding)
    }

    // MARK: - Frame Calculation Tests

    func testCalculateItemFramesWithoutNotch() {
        let widths: [CGFloat] = [20, 30, 40]
        let frames = controller.calculateItemFrames(
            itemWidths: widths,
            startX: 0,
            spacing: 10,
            itemHeight: 24,
            yPosition: 0,
            notchRect: nil
        )

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0], CGRect(x: 0, y: 0, width: 20, height: 24))
        XCTAssertEqual(frames[1], CGRect(x: 30, y: 0, width: 30, height: 24)) // 0 + 20 + 10 = 30
        XCTAssertEqual(frames[2], CGRect(x: 70, y: 0, width: 40, height: 24)) // 30 + 30 + 10 = 70
    }

    func testCalculateItemFramesWithNotchCollision() {
        let widths: [CGFloat] = [50, 50, 50]
        let notchRect = CGRect(x: 600, y: 0, width: 200, height: 30) // notch from 600 to 800

        let frames = controller.calculateItemFrames(
            itemWidths: widths,
            startX: 500,
            spacing: 10,
            itemHeight: 24,
            yPosition: 0,
            notchRect: notchRect
        )

        XCTAssertEqual(frames.count, 3)
        // Item 0: starts at 500, width 50, ends at 550 (before notch)
        XCTAssertEqual(frames[0], CGRect(x: 500, y: 0, width: 50, height: 24))

        // Item 1: next start is 500 + 50 + 10 = 560. 560 + 50 = 610 >= 600 (collides!). Jumps to 800
        XCTAssertEqual(frames[1], CGRect(x: 800, y: 0, width: 50, height: 24))

        // Item 2: starts at 800 + 50 + 10 = 860.
        XCTAssertEqual(frames[2], CGRect(x: 860, y: 0, width: 50, height: 24))
    }

    func testCalculateItemFramesWithItemConfigs() {
        let items = [
            ItemConfig(id: "item1", category: .hiddenOnHover),
            ItemConfig(id: "item2", category: .hiddenOnHover),
            ItemConfig(id: "item3", category: .hiddenOnHover)
        ]

        let frames = controller.calculateItemFrames(
            items: items,
            defaultItemWidth: 22.0,
            startX: 100,
            spacing: 8.0,
            itemHeight: 22.0,
            yPosition: 2.0,
            notchRect: nil
        )

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0], CGRect(x: 100, y: 2, width: 22, height: 22))
        XCTAssertEqual(frames[1], CGRect(x: 130, y: 2, width: 22, height: 22))
        XCTAssertEqual(frames[2], CGRect(x: 160, y: 2, width: 22, height: 22))
    }

    func testCalculateTotalWidth() {
        XCTAssertEqual(controller.calculateTotalWidth(itemWidths: [], spacing: 10), 0)
        XCTAssertEqual(controller.calculateTotalWidth(itemWidths: [20], spacing: 10), 20)
        XCTAssertEqual(controller.calculateTotalWidth(itemWidths: [20, 30, 40], spacing: 10), 110) // 20 + 10 + 30 + 10 + 40 = 110
    }
}
