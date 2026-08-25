import SwiftUI

/// Clean, minimal Preferences View for CleanBar.
public struct SettingsView: View {
    @ObservedObject public var observer: StatusBarObserver
    @StateObject private var launchAtLoginService = LaunchAtLoginService()
    public let stateStore: StateStore
    public var onShowInstructions: (() -> Void)?

    @State private var selectedStyle: BarShelfStyle = .auto

    public init(
        observer: StatusBarObserver,
        stateStore: StateStore? = nil,
        onShowInstructions: (() -> Void)? = nil
    ) {
        self.observer = observer
        self.stateStore = stateStore ?? observer.stateStore
        self.onShowInstructions = onShowInstructions
        _selectedStyle = State(initialValue: (stateStore ?? observer.stateStore).barShelfStyle)
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
                }

                Spacer()
            }

            Divider()

            // General Settings Group
            VStack(alignment: .leading, spacing: 10) {
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
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // Bar Presentation Style Card (Inline, Auto, Floating)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reveal Style")
                                .font(.body)
                                .bold()
                            Text("Mode for displaying hidden status bar icons on hover.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("", selection: Binding(
                            get: { selectedStyle },
                            set: { newStyle in
                                selectedStyle = newStyle
                                stateStore.barShelfStyle = newStyle
                            }
                        )) {
                            ForEach(BarShelfStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }

                    Text(selectedStyle.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
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
            selectedStyle = stateStore.barShelfStyle
        }
    }
}
