import SwiftUI
import UniformTypeIdentifiers

/// Clean, minimal Preferences View for CleanBar.
public struct SettingsView: View {
    @ObservedObject public var observer: StatusBarObserver
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    @State private var draggedID: String?
    @State private var targetedID: String?
    public let stateStore: StateStore
    public var onShowInstructions: (() -> Void)?
    public var onSetItemHidden: ((StatusItemModel, Bool) -> Void)?

    public init(
        observer: StatusBarObserver,
        stateStore: StateStore? = nil,
        onShowInstructions: (() -> Void)? = nil,
        onSetItemHidden: ((StatusItemModel, Bool) -> Void)? = nil
    ) {
        self.observer = observer
        self.stateStore = stateStore ?? observer.stateStore
        self.onShowInstructions = onShowInstructions
        self.onSetItemHidden = onSetItemHidden
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CleanBar Preferences")
                        .font(.title3)
                        .bold()
                    Text("Organize and declutter your macOS menu bar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()

            // General Settings Group
            VStack(alignment: .leading, spacing: 12) {
                Text("General Settings")
                    .font(.headline)
                    .foregroundColor(.primary)

                // Launch at Login Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.body)
                                .bold()
                            Text("Automatically start CleanBar when logging in.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { launchAtLoginService.isEnabled },
                            set: { launchAtLoginService.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    }

                    if let msg = launchAtLoginService.statusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // Hidden Items Management
            if !observer.leftHiddenItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hidden Items")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Toggle an item to move it to the right of the Eye (visible) or keep it hidden on the left.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(observer.leftHiddenItems) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .contentShape(Rectangle())
                                        .onDrag {
                                            draggedID = item.id
                                            return NSItemProvider(object: item.id as NSString)
                                        }
                                    if let icon = item.iconImage {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "menubar.rectangle")
                                            .font(.system(size: 12))
                                    }
                                    Text(item.subtitle.isEmpty ? item.appName : item.subtitle)
                                        .font(.body)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { true },
                                        set: { newVal in onSetItemHidden?(item, newVal) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(targetedID == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .onDrop(of: [.text], isTargeted: Binding(
                                    get: { targetedID == item.id },
                                    set: { isT in
                                        if isT { targetedID = item.id }
                                        else if targetedID == item.id { targetedID = nil }
                                    }
                                )) { providers in
                                    if let id = draggedID, id != item.id {
                                        observer.moveItem(id: id, before: item.id)
                                    }
                                    draggedID = nil
                                    targetedID = nil
                                    return true
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // ScrollView on macOS has no intrinsic height: a maxHeight alone
                    // collapses it to 0 inside the popover. Give it an explicit height
                    // that fits the rows (capped so many items still scroll).
                    .frame(height: min(200, max(36, CGFloat(observer.leftHiddenItems.count) * 30 + 8)))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }

            // Accessibility Banner if permission is not granted
            if !observer.isAccessibilityTrusted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access Required")
                            .font(.subheadline)
                            .bold()
                        Text("Required to detect menu bar mouse movements.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Grant Access") {
                        observer.checkAccessibilityPermissions(prompt: true)
                        observer.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }

            Divider()

            // Bottom Actions Bar
            HStack {
                Button(action: {
                    onShowInstructions?()
                }) {
                    Label("Setup Guide", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit CleanBar", systemImage: "power")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 440)
        .alert("Applications Folder Required", isPresented: $launchAtLoginService.showInstallationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To enable Launch at Login, please move CleanBar to your Applications folder (/Applications) first.")
        }
        .onAppear {
            launchAtLoginService.checkStatus()
            NSLog("🪟 SettingsView: onAppear items=\(observer.leftHiddenItems.count)")
        }
        .onChange(of: observer.leftHiddenItems.count) { _, count in
            NSLog("🪟 SettingsView: items cambiato a \(count)")
        }
        .frame(width: 520)
    }
}
