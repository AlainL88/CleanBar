import SwiftUI

/// Onboarding / User Instructions View explaining CleanBar setup, controls, and preferences.
public struct OnboardingView: View {
    public var onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to CleanBar")
                        .font(.title2)
                        .bold()
                    Text("Organize and declutter your macOS menu bar.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Instructions Steps
            VStack(alignment: .leading, spacing: 14) {
                InstructionRow(
                    stepNumber: 1,
                    iconName: "lock.shield",
                    title: "Grant Accessibility Access",
                    description: "CleanBar needs Accessibility permissions to detect when your mouse moves over the menu bar."
                )

                InstructionRow(
                    stepNumber: 2,
                    iconName: "command",
                    title: "Arrange Your Icons",
                    description: "Hold Command (⌘) and drag any menu bar icon to the left of CleanBar's Eye icon to hide it."
                )

                InstructionRow(
                    stepNumber: 3,
                    iconName: "cursorarrow.motionlines",
                    title: "Hover & Reveal Controls",
                    description: "Move your cursor over the top menu bar to reveal hidden icons. Left-click the Eye icon for Preferences."
                )

                InstructionRow(
                    stepNumber: 4,
                    iconName: "slider.horizontal.3",
                    title: "Preferences & Reveal Styles",
                    description: "Configure Launch at Login and choose your Reveal Style: Inline (menu bar), Floating (glass shelf), or Auto (recommended)."
                )
            }
            .padding(.vertical, 2)

            Divider()

            // Dismiss Button
            HStack {
                Spacer()
                Button(action: {
                    onDismiss?()
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(22)
        .frame(width: 500, height: 440)
    }
}

private struct InstructionRow: View {
    let stepNumber: Int
    let iconName: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(stepNumber): \(title)")
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
