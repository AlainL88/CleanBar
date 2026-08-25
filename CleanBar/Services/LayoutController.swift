import Cocoa
import ApplicationServices

public enum SpacingMode: Equatable {
    case standard
    case compact
    case custom(CGFloat)
}

/// Coordinates status item layout, visibility transitions, and screen boundaries.
@MainActor
public final class LayoutController {
    public static let standardPadding: CGFloat = 16.0
    public static let compactPadding: CGFloat = 8.0

    public private(set) var currentPadding: CGFloat = 0.0

    public init() {}

    /// Computes the hardware camera notch rectangle in screen coordinates.
    public func computeNotchRect(for screen: NSScreen) -> CGRect? {
        if #available(macOS 12.0, *) {
            return computeNotchRect(
                topLeft: screen.auxiliaryTopLeftArea,
                topRight: screen.auxiliaryTopRightArea,
                screenHeight: screen.frame.height
            )
        }
        return nil
    }

    /// Computes notch rect from auxiliary top areas.
    public func computeNotchRect(topLeft: CGRect?, topRight: CGRect?, screenHeight: CGFloat) -> CGRect? {
        guard let topLeft = topLeft, let topRight = topRight,
              topLeft.width > 0, topRight.width > 0 else {
            return nil
        }

        let notchX = topLeft.maxX
        let notchWidth = topRight.minX - topLeft.maxX
        guard notchWidth > 0 else { return nil }

        let notchY = topLeft.origin.y
        let notchHeight = topLeft.height

        return CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }

    /// Calculates the next X position for an item, jumping past the notch if an intersection occurs.
    public func nextXPosition(currentX: CGFloat, itemWidth: CGFloat, notchRect: CGRect?) -> CGFloat {
        let proposedRect = CGRect(x: currentX, y: 0, width: itemWidth, height: 24)

        if let notch = notchRect, notch.width > 0 {
            if proposedRect.intersects(notch) || (currentX >= notch.minX && currentX < notch.maxX) || (currentX < notch.minX && (currentX + itemWidth) >= notch.minX) {
                return notch.maxX
            }
        }

        return currentX + itemWidth
    }

    /// Returns padding for spacing mode.
    public func padding(for mode: SpacingMode) -> CGFloat {
        switch mode {
        case .standard: return Self.standardPadding
        case .compact: return Self.compactPadding
        case .custom(let val): return val
        }
    }

    /// Resolves spacing for expanded or collapsed state.
    public func resolveSpacing(isExpanded: Bool, totalItemsWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard isExpanded else { return Self.standardPadding }
        return totalItemsWidth > availableWidth ? Self.compactPadding : Self.standardPadding
    }

    /// Calculates item frames with notch collision avoidance.
    public func calculateItemFrames(
        itemWidths: [CGFloat],
        startX: CGFloat,
        spacing: CGFloat,
        itemHeight: CGFloat,
        yPosition: CGFloat,
        notchRect: CGRect?
    ) -> [CGRect] {
        var frames: [CGRect] = []
        var currentX = startX

        for (index, width) in itemWidths.enumerated() {
            if index > 0 {
                currentX += spacing
            }

            if let notch = notchRect, notch.width > 0 {
                let proposedRect = CGRect(x: currentX, y: 0, width: width, height: itemHeight)
                if proposedRect.intersects(notch) || (currentX >= notch.minX && currentX < notch.maxX) || ((currentX + width) > notch.minX && currentX < notch.minX) {
                    currentX = notch.maxX
                }
            }

            frames.append(CGRect(x: currentX, y: yPosition, width: width, height: itemHeight))
            currentX += width
        }

        return frames
    }

    /// Overload for ItemConfig items.
    public func calculateItemFrames(
        items: [ItemConfig],
        defaultItemWidth: CGFloat,
        startX: CGFloat,
        spacing: CGFloat,
        itemHeight: CGFloat,
        yPosition: CGFloat,
        notchRect: CGRect?
    ) -> [CGRect] {
        let widths = Array(repeating: defaultItemWidth, count: items.count)
        return calculateItemFrames(
            itemWidths: widths,
            startX: startX,
            spacing: spacing,
            itemHeight: itemHeight,
            yPosition: yPosition,
            notchRect: notchRect
        )
    }

    /// Calculates total width of items plus inter-item spacing.
    public func calculateTotalWidth(itemWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        guard !itemWidths.isEmpty else { return 0 }
        let totalItems = itemWidths.reduce(0, +)
        let totalSpacing = CGFloat(itemWidths.count - 1) * spacing
        return totalItems + totalSpacing
    }

    /// Adjusts inter-item padding.
    public func adjustPadding(compact: Bool) {
        currentPadding = compact ? 2.0 : 8.0
    }

    // MARK: - Visibility Control

    public let spacerController = MenuBarSpacerController()

    /// Applies visibility masking to status items based on hover state.
    public func applyVisibility(isHovered: Bool, observer: StatusBarObserver) {
        let items = observer.discoveredItems
        let tempRevealed = observer.temporarilyRevealedItemIDs

        let hasHiddenItems = items.contains { !tempRevealed.contains($0.id) }

        // Force expanded state while popover is open so the popover never shifts position
        let effectiveHovered = isHovered || spacerController.isPopoverShown

        if Thread.isMainThread {
            spacerController.setExpanded(effectiveHovered, hiddenItemsCount: hasHiddenItems ? items.count : 0)
        } else {
            DispatchQueue.main.async {
                self.spacerController.setExpanded(effectiveHovered, hiddenItemsCount: hasHiddenItems ? items.count : 0)
            }
        }
    }
}
