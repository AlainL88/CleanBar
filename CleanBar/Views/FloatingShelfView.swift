import SwiftUI
import Cocoa

/// Interactive floating sub-bar view displaying the true menu bar icons of items hidden to the left of CleanBar.
public struct FloatingShelfView: View {
    @ObservedObject public var observer: StatusBarObserver
    public var onOpenPreferences: (() -> Void)?

    public init(observer: StatusBarObserver, onOpenPreferences: (() -> Void)? = nil) {
        self.observer = observer
        self.onOpenPreferences = onOpenPreferences
    }

    public var body: some View {
        HStack(spacing: 6) {
            if observer.leftHiddenItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .foregroundColor(.secondary)
                    Text("⌘ Drag icons to the left of CleanBar to hide")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
            } else {
                ForEach(observer.leftHiddenItems) { item in
                    FloatingShelfStatusItemTile(item: item, observer: observer)
                }
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            // Preferences Quick Action
            Button(action: {
                onOpenPreferences?()
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("CleanBar Preferences")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct FloatingShelfStatusItemTile: View {
    let item: StatusItemModel
    let observer: StatusBarObserver
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            observer.triggerStatusItem(item)
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.clear)
                    .frame(width: max(26, item.frame.width), height: 26)

                if let icon = item.iconImage {
                    Image(nsImage: icon)
                        .renderingMode(icon.isTemplate ? .template : .original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .foregroundColor(.primary)
                        .frame(width: max(18, min(24, item.frame.width - 4)), height: 18)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .help(item.appName)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
