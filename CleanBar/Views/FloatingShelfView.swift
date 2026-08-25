import SwiftUI
import Cocoa

/// Interactive floating sub-bar view displaying all menu bar items under the menu bar.
public struct FloatingShelfView: View {
    @ObservedObject public var observer: StatusBarObserver
    public var onOpenPreferences: (() -> Void)?

    public init(observer: StatusBarObserver, onOpenPreferences: (() -> Void)? = nil) {
        self.observer = observer
        self.onOpenPreferences = onOpenPreferences
    }

    public var body: some View {
        HStack(spacing: 6) {
            if observer.discoveredItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "menubar.rectangle")
                        .foregroundColor(.secondary)
                    Text("Scanning Menu Bar Items...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
            } else {
                ForEach(observer.discoveredItems) { item in
                    FloatingShelfItemTile(item: item, observer: observer)
                }
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            // Preferences Quick Action
            Button(action: {
                onOpenPreferences?()
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("CleanBar Preferences")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct FloatingShelfItemTile: View {
    let item: ItemConfig
    let observer: StatusBarObserver
    @State private var isHovered: Bool = false

    var body: some View {
        let app = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == item.id || $0.localizedName == item.id
        }
        let icon = app?.icon ?? NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities")
        let name = app?.localizedName ?? item.id

        Button(action: {
            observer.triggerItem(id: item.id)
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.clear)
                    .frame(width: 28, height: 28)

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
        }
        .buttonStyle(.plain)
        .help(name)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
