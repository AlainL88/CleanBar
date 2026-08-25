import Cocoa

/// Spacing configuration modes for status bar item layout.
public enum SpacingMode: Equatable {
    case standard
    case compact
    case custom(CGFloat)
}

/// Layout and Notch Engine responsible for positioning status items,
/// calculating hardware notch collisions, and adjusting spacing.
@MainActor
public final class LayoutController {
    public static let standardPadding: CGFloat = 16.0
    public static let compactPadding: CGFloat = 8.0

    public init() {}

    // MARK: - Notch Calculation

    /// Computes the physical notch rectangle for a given `NSScreen` using auxiliary top areas.
    /// Returns `nil` if the screen does not have a notch or is invalid.
    public func computeNotchRect(for screen: NSScreen) -> CGRect? {
        computeNotchRect(
            topLeft: screen.auxiliaryTopLeftArea,
            topRight: screen.auxiliaryTopRightArea,
            screenHeight: screen.frame.height
        )
    }

    /// Computes notch bounds given optional auxiliary top-left and top-right areas and screen height.
    public func computeNotchRect(topLeft: CGRect?, topRight: CGRect?, screenHeight: CGFloat) -> CGRect? {
        guard let topLeft = topLeft,
              let topRight = topRight else {
            return nil
        }
        let minX = topLeft.maxX
        let maxX = topRight.minX
        guard maxX > minX else {
            return nil
        }
        let notchHeight = topLeft.height > 0 ? topLeft.height : max(0, screenHeight - topLeft.minY)
        return CGRect(x: minX, y: topLeft.minY, width: maxX - minX, height: notchHeight)
    }

    // MARK: - Positioning & Collision Avoidance

    /// Calculates the next horizontal position for an item.
    /// If placing the item at `currentX` would collide with or lie within `notchRect`,
    /// this jumps past `notchRect.maxX` to avoid the physical notch hardware.
    public func nextXPosition(currentX: CGFloat, itemWidth: CGFloat, notchRect: CGRect?) -> CGFloat {
        guard let notch = notchRect, notch.width > 0 else {
            return currentX + itemWidth
        }

        let itemEndX = currentX + max(0, itemWidth)
        // If the item range intersects [notch.minX, notch.maxX)
        if itemEndX >= notch.minX && currentX < notch.maxX {
            return notch.maxX
        }

        return currentX + itemWidth
    }

    // MARK: - Spacing Logic

    /// Returns the padding value in points for a given `SpacingMode`.
    public func padding(for mode: SpacingMode) -> CGFloat {
        switch mode {
        case .standard:
            return Self.standardPadding
        case .compact:
            return Self.compactPadding
        case .custom(let value):
            return value
        }
    }

    /// Resolves the effective padding based on expansion state and available space.
    public func resolveSpacing(isExpanded: Bool, totalItemsWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard isExpanded else {
            return Self.standardPadding
        }
        if totalItemsWidth > availableWidth {
            return Self.compactPadding
        }
        return Self.standardPadding
    }

    /// Resolves the `SpacingMode` based on expansion state and available space.
    public func resolveSpacingMode(isExpanded: Bool, totalItemsWidth: CGFloat, availableWidth: CGFloat) -> SpacingMode {
        let pad = resolveSpacing(isExpanded: isExpanded, totalItemsWidth: totalItemsWidth, availableWidth: availableWidth)
        if pad == Self.compactPadding {
            return .compact
        }
        return .standard
    }

    /// Calculates the total horizontal span for an array of item widths and inter-item spacing.
    public func calculateTotalWidth(itemWidths: [CGFloat], spacing: CGFloat) -> CGFloat {
        guard !itemWidths.isEmpty else { return 0 }
        let totalItems = itemWidths.reduce(0, +)
        let totalSpacing = CGFloat(max(0, itemWidths.count - 1)) * spacing
        return totalItems + totalSpacing
    }

    // MARK: - Frame Calculation

    /// Calculates individual frames for a list of item widths, accounting for spacing and notch avoidance.
    public func calculateItemFrames(
        itemWidths: [CGFloat],
        startX: CGFloat = 0,
        spacing: CGFloat = 8.0,
        itemHeight: CGFloat = 24.0,
        yPosition: CGFloat = 0,
        notchRect: CGRect? = nil
    ) -> [CGRect] {
        var frames: [CGRect] = []
        var currentX = startX

        for width in itemWidths {
            // Check if current starting point or item body collides with notch
            if let notch = notchRect, notch.width > 0 {
                let itemEndX = currentX + width
                if itemEndX >= notch.minX && currentX < notch.maxX {
                    currentX = notch.maxX
                }
            }

            let frame = CGRect(x: currentX, y: yPosition, width: width, height: itemHeight)
            frames.append(frame)

            // Advance position for next item
            currentX = nextXPosition(currentX: currentX + width, itemWidth: spacing, notchRect: notchRect)
        }

        return frames
    }

    /// Convenience overload calculating frames for an array of `ItemConfig` models.
    public func calculateItemFrames(
        items: [ItemConfig],
        defaultItemWidth: CGFloat = 22.0,
        startX: CGFloat = 0,
        spacing: CGFloat = 8.0,
        itemHeight: CGFloat = 24.0,
        yPosition: CGFloat = 0,
        notchRect: CGRect? = nil
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

    // MARK: - Visibility Control

    public let spacerController = MenuBarSpacerController()

    /// Applies visibility masking to status items based on hover state, categories, and notification reveals.
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

    private func setAXVisibility(_ visible: Bool, forID id: String) {
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == id }
        for runningApp in runningApps {
            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
            var extrasMenuBar: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasMenuBar) == .success,
               let extras = extrasMenuBar {
                AXUIElementSetAttributeValue(extras as! AXUIElement, kAXHiddenAttribute as CFString, (!visible) as CFBoolean)
            }
        }
    }
}
