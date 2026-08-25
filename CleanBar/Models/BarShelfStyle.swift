import Foundation

/// Style of bar-shelf presentation when revealing hidden menu bar items.
public enum BarShelfStyle: String, Codable, CaseIterable, Identifiable {
    case inline = "inline"
    case auto = "auto"
    case floating = "floating"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inline:
            return "Inline"
        case .auto:
            return "Auto (Recommended)"
        case .floating:
            return "Floating"
        }
    }

    public var description: String {
        switch self {
        case .inline:
            return "Expand hidden icons directly inside the top menu bar."
        case .auto:
            return "Inline when space permits; automatically floats when space is tight."
        case .floating:
            return "Always present hidden icons in a floating glass bar below the menu bar."
        }
    }
}
