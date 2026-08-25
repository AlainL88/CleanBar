import SwiftUI

/// Onboarding / User Instructions View explaining CleanBar setup and controls.
public struct OnboardingView: View {
    public var onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
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
            VStack(alignment: .leading, spacing: 16) {
                InstructionRow(
                    stepNumber: 1,
                    iconName: "lock.shield",
                    title: "Grant Accessibility Access",
                    description: "CleanBar needs Accessibility permissions to detect when your mouse moves over the top menu bar."
                )

                InstructionRow(
                    stepNumber: 2,
                    iconName: "command",
                    title: "Arrange Your Icons",
                    description: "Hold Command (⌘) and drag any menu bar icons to the left of CleanBar's Eye icon to hide them."
                )

                InstructionRow(
                    stepNumber: 3,
                    iconName: "cursorarrow.motionlines",
                    title: "Hover to Reveal",
                    description: "Move your mouse over the menu bar to reveal hidden icons. Left-click the Eye icon for Preferences."
                )
            }
            .padding(.vertical, 4)

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
        .padding(24)
        .frame(width: 480, height: 380)
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
                    .frame(width: 36, height: 36)

                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Step \(stepNumber): \(title)")
                    .font(.headline)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
