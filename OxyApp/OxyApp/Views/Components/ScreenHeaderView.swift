import SwiftUI

/// The standard page header: a system back chevron above a large title, as a large-title
/// navigation bar reads on iOS.
struct ScreenHeaderView: View {
    @Environment(AppState.self) private var appState
    let title: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                backButton
                Spacer(minLength: 0)
                sampleLabel
            }
            .frame(minHeight: onBack == nil ? 8 : 44)
            heading
                .padding(.horizontal, AppSpacing.margin)
                .padding(.bottom, AppSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground.ignoresSafeArea(edges: .top))
    }

    private var heading: some View {
        Text(title)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(Color.appInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, AppSpacing.sm)
            .accessibilityLabel("Back")
        }
    }

    @ViewBuilder
    private var sampleLabel: some View {
        if appState.isDemoSession {
            Text("Sample")
                .font(.caption)
                .foregroundStyle(Color.appMuted)
                .padding(.trailing, AppSpacing.margin)
        }
    }
}
