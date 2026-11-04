import SwiftUI

struct ErrorBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let message: String
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Text(message)
                .font(.role(.footnote))
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }

            if let onRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.app(.secondary, fullWidth: false))
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    AppIcon("xmark", size: 12)
                        .foregroundStyle(Color.appMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.appScale)
                .accessibilityLabel("Dismiss error")
            }
        }
        .appCard(padding: AppSpacing.md)
    }
}

#Preview {
    ErrorBanner(message: "Network connection lost", onRetry: {}, onDismiss: {})
        .background(Color.appObsidian)
}
