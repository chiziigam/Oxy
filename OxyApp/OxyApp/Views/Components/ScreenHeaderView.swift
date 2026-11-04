import SwiftUI

struct ScreenHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                HStack {
                    backButton
                    Spacer()
                    sampleLabel
                }
                heading
            } else {
                HStack(spacing: 10) {
                    backButton
                    heading
                    Spacer(minLength: 0)
                    sampleLabel
                }
            }
        }
        .padding(.horizontal, AppSpacing.margin)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(Color.appBackground.ignoresSafeArea(edges: .top))
    }

    private var heading: some View {
        Text(title)
            .font(.screenTitle)
            .foregroundStyle(Color.appInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button {
                HapticManager.shared.impact(.light)
                onBack()
            } label: {
                AppIcon("chevron-left", size: 17)
                    .foregroundStyle(Color.appInk)
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface2, in: Circle())
            }
            .buttonStyle(.appScale)
            .accessibilityLabel("Back")
        }
    }

    @ViewBuilder
    private var sampleLabel: some View {
        if appState.isDemoSession {
            Text("Sample")
                .font(.role(.caption, weight: .medium))
                .foregroundStyle(Color.appMuted)
        }
    }
}
