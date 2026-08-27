import Cocoa

/// Represents an individual menu bar status item with its on-screen frame and captured icon.
public struct StatusItemModel: Identifiable, Equatable {
    public let id: String
    public let appName: String
    public let frame: CGRect
    public let iconImage: NSImage?
    public let axElement: AXUIElement?
    /// Extra detail from the item's AX title — e.g. the OneDrive account
    /// ("OneDrive — Personale"). Shown in the shelf tooltip.
    public let subtitle: String
    /// True when the app's AX frame is broken (always reports -4000, e.g. OneDrive),
    /// so its real bar position is unknown. Such items sit next to the Eye, i.e.
    /// at the RIGHT end of the hidden section — the shelf must show them last.
    public let isBrokenAX: Bool

    public init(
        id: String,
        appName: String,
        frame: CGRect,
        iconImage: NSImage?,
        axElement: AXUIElement? = nil,
        subtitle: String = "",
        isBrokenAX: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.frame = frame
        self.iconImage = iconImage
        self.axElement = axElement
        self.subtitle = subtitle
        self.isBrokenAX = isBrokenAX
    }

    public static func == (lhs: StatusItemModel, rhs: StatusItemModel) -> Bool {
        return lhs.id == rhs.id && lhs.frame == rhs.frame
    }
}
