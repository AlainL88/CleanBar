import SwiftUI
import Cocoa

/// Interactive floating sub-bar view displaying the true menu bar icons of items hidden to the left of CleanBar.
public struct FloatingShelfView: View {
    @ObservedObject public var observer: StatusBarObserver
    public var onOpenPreferences: (() -> Void)?
    public var onItemClicked: (() -> Void)?

    public init(
        observer: StatusBarObserver,
        onOpenPreferences: (() -> Void)? = nil,
        onItemClicked: (() -> Void)? = nil
    ) {
        self.observer = observer
        self.onOpenPreferences = onOpenPreferences
        self.onItemClicked = onItemClicked
    }

    public var body: some View {
        HStack(spacing: 8) {
            if observer.leftHiddenItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Trascina le icone a sinistra dell'Occhio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 6)
            } else {
                ForEach(observer.leftHiddenItems) { item in
                    FloatingShelfStatusItemTile(
                        item: item,
                        observer: observer,
                        onClicked: {
                            onItemClicked?()
                        }
                    )
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
            .help("Impostazioni CleanBar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct FloatingShelfStatusItemTile: View {
    let item: StatusItemModel
    let observer: StatusBarObserver
    var onClicked: (() -> Void)?
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: {
            onClicked?()
            observer.triggerStatusItem(item)
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.18) : Color.clear)
                    .frame(width: max(28, item.frame.width), height: 28)

                if let icon = item.iconImage {
                    Image(nsImage: icon)
                        .renderingMode(icon.isTemplate ? .template : .original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .foregroundColor(.primary)
                        .frame(width: 18, height: 18)
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
