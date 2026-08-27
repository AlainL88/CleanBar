import SwiftUI
import Cocoa

/// Interactive floating sub-bar view displaying the true menu bar icons of items hidden to the left of CleanBar.
public struct FloatingShelfView: View {
    @ObservedObject public var observer: StatusBarObserver
    public var onOpenPreferences: (() -> Void)?
    public var onItemClicked: ((StatusItemModel) -> Void)?
    public var onItemHover: ((StatusItemModel, CGRect) -> Void)?
    public var onHoverEnd: (() -> Void)?

    public init(
        observer: StatusBarObserver,
        onOpenPreferences: (() -> Void)? = nil,
        onItemClicked: ((StatusItemModel) -> Void)? = nil,
        onItemHover: ((StatusItemModel, CGRect) -> Void)? = nil,
        onHoverEnd: (() -> Void)? = nil
    ) {
        self.observer = observer
        self.onOpenPreferences = onOpenPreferences
        self.onItemClicked = onItemClicked
        self.onItemHover = onItemHover
        self.onHoverEnd = onHoverEnd
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
                        onClicked: {
                            onItemClicked?(item)
                        },
                        onHover: { frameInWindow in
                            onItemHover?(item, frameInWindow)
                        },
                        onHoverEnd: {
                            onHoverEnd?()
                        },
                        onCmdDragEnd: { delta in
                            reorder(itemID: item.id, byDelta: delta)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    /// Cmd+drag a shelf tile to reorder it. Each tile is ~34pt wide + 8pt spacing,
    /// so the horizontal drag distance maps to a number of positions to shift.
    private func reorder(itemID: String, byDelta delta: CGFloat) {
        let items = observer.leftHiddenItems
        guard let fromIdx = items.firstIndex(where: { $0.id == itemID }) else { return }
        let step = Int(round(delta / 40))
        let toIdx = max(0, min(items.count - 1, fromIdx + step))
        guard toIdx != fromIdx else { return }
        observer.moveItem(id: itemID, toIndex: toIdx)
    }
}

private struct FloatingShelfStatusItemTile: View {
    let item: StatusItemModel
    var onClicked: (() -> Void)?
    var onHover: ((CGRect) -> Void)?
    var onHoverEnd: (() -> Void)?
    var onCmdDragEnd: ((CGFloat) -> Void)?
    @State private var isHovered: Bool = false
    @State private var frameInWindow: CGRect = .zero

    var body: some View {
        Button(action: {
            onClicked?()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.18) : Color.clear)
                    .frame(width: max(24, item.frame.width), height: 22)

                if let icon = item.iconImage {
                    Image(nsImage: icon)
                        .renderingMode(icon.isTemplate ? .template : .original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        // Template glyphs take the shelf's foreground (white on the
                        // dark material) so they never wash out.
                        .foregroundColor(.primary)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frameInWindow = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in frameInWindow = f }
            }
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovered = hovering
            }
            if hovering {
                onHover?(frameInWindow)
            } else {
                onHoverEnd?()
            }
        }
        // Cmd+drag a tile to reorder it inside the shelf (a plain click still
        // opens the item's menu).
        .gesture(
            DragGesture(minimumDistance: 5)
                .onEnded { value in
                    // DragGesture.Value exposes no modifiers; the current event
                    // (mouse up) still carries them.
                    guard NSEvent.modifierFlags.contains(.command) else { return }
                    onCmdDragEnd?(value.translation.width)
                }
        )
    }
}
