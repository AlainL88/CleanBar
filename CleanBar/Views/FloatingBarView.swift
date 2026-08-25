import SwiftUI
import Cocoa

/// Floating glass bar-shelf view showing hidden menu bar items horizontally.
public struct FloatingBarView: View {
    @ObservedObject public var observer: StatusBarObserver
    public var onDismiss: (() -> Void)?

    public init(observer: StatusBarObserver, onDismiss: (() -> Void)? = nil) {
        self.observer = observer
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            let hiddenItems = observer.discoveredItems.filter { $0.category == .hiddenOnHover || $0.category == .deepHidden }
            let displayItems = hiddenItems.isEmpty ? observer.discoveredItems : hiddenItems

            if displayItems.isEmpty {
                Text("No hidden icons")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(displayItems) { item in
                    FloatingBarItemButton(itemID: item.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct FloatingBarItemButton: View {
    let itemID: String
    @State private var isHovered: Bool = false

    var body: some View {
        let app = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == itemID || $0.localizedName == itemID
        }
        let icon = app?.icon ?? NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities")
        let appName = app?.localizedName ?? itemID

        Button(action: {
            if let app = app {
                app.activate()
            }
        }) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(appName)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
