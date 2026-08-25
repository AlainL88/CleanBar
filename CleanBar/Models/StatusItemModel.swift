import Cocoa

/// Represents an individual menu bar status item with its on-screen frame and captured icon.
public struct StatusItemModel: Identifiable, Equatable {
    public let id: String
    public let appName: String
    public let frame: CGRect
    public let iconImage: NSImage?
    public let axElement: AXUIElement?

    public init(
        id: String,
        appName: String,
        frame: CGRect,
        iconImage: NSImage?,
        axElement: AXUIElement? = nil
    ) {
        self.id = id
        self.appName = appName
        self.frame = frame
        self.iconImage = iconImage
        self.axElement = axElement
    }

    public static func == (lhs: StatusItemModel, rhs: StatusItemModel) -> Bool {
        return lhs.id == rhs.id && lhs.frame == rhs.frame
    }
}
