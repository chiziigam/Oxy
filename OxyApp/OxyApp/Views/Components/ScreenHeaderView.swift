import SwiftUI

/// The bar every screen opens with: one title, one way back, in the same type as the main screen.
struct ScreenHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            if let onBack {
                Button(action: onBack) {
                    AppIcon("chevron-left", size: 18)
                        .foregroundStyle(Color.adamInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .padding(.leading, -12)
            }
            Text(title)
                .font(typeSize.isAccessibilitySize ? .appBody(20, weight: .semibold) : .adamTitle)
                .foregroundStyle(Color.adamInk)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if appState.isDemoSession {
                Text("Sample")
                    .font(.adamLabel)
                    .foregroundStyle(Color.adamMuted)
            }
        }
        .padding(.horizontal, AdamLayout.gutter)
        .frame(minHeight: 52)
        .background(Color.adamBackground.ignoresSafeArea(edges: .top))
    }
}
