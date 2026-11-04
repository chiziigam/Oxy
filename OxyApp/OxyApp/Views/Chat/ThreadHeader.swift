import SwiftUI

/// Navigation has its own space, clear of the conversation.
struct ThreadHeader: View {
    var isIncognito: Bool
    var isWorking: Bool
    var activity: AdamActivityState? = nil
    var deviceOnline: Bool
    var isDemo = false
    var isComposing = false
    var showsStatus = true
    /// Set while in the conversation: the way back to Home.
    var onHome: (() -> Void)? = nil
    /// On Now, the greeting; in the conversation, the request it is about.
    var title: String = "Home"
    /// On Home: the line under the title, with its colour.
    var homeStatus: (text: String, color: Color)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var wheelOpen: Bool
    @Binding var hubCenter: CGPoint

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let onHome {
                Button {
                    HapticManager.shared.impact(.light)
                    onHome()
                } label: {
                    AppIcon("chevron-left", size: 17)
                        .foregroundStyle(Color.appInk)
                        .frame(width: 44, height: 44)
                        .background(Color.appSurface2, in: Circle())
                }
                .buttonStyle(.appScale)
                .accessibilityLabel("Back to Now")
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(title)
                        .font(onHome == nil ? Font.role(.title, weight: .bold) : Font.role(.body, weight: .semibold))
                        .foregroundStyle(Color.appInk)
                        .lineLimit(onHome == nil && typeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.tail)
                        .accessibilityAddTraits(.isHeader)
                    if isDemo {
                        Text("Sample").font(.role(.caption, weight: .medium)).foregroundStyle(Color.appMuted)
                    }
                }
                if let homeStatus, !isIncognito, onHome == nil {
                    HStack(spacing: 7) {
                        Circle().fill(homeStatus.color).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(homeStatus.text).font(.role(.footnote, weight: .medium)).foregroundStyle(Color.appMuted)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }
                    .accessibilityElement(children: .combine)
                } else if isIncognito {
                    Text("Not saved").font(.role(.footnote, weight: .medium)).foregroundStyle(Color.appMuted)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            // The wheel is the one navigation control; its accessible list fallback lives inside it.
            Button {
                HapticManager.shared.impact(.light)
                wheelOpen = true
            } label: {
                WheelHub(progress: 0, incognito: isIncognito)
                    .overlay(alignment: .topTrailing) { statusDot }
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        let frame = proxy.frame(in: .global)
                        return CGPoint(x: frame.midX, y: frame.midY)
                    } action: { hubCenter = $0 }
                    .contentShape(Circle())
            }
            .buttonStyle(.appScale)
            .opacity(wheelOpen ? 0 : 1)
            .accessibilityLabel("Menu")
            .accessibilityHint("Opens Today, Activity, Memory, Your home and Settings")
            .accessibilityValue(isIncognito ? "Private mode on" : (visibleStatus ?? ""))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, AppSpacing.chatMargin)
        .padding(.vertical, AppSpacing.sm)
        .frame(minHeight: 60)
        .background(Color.appBackground.ignoresSafeArea(edges: .top))
        .animation(.appStandard, value: activity)
        .animation(.appStandard, value: deviceOnline)
    }

    @ViewBuilder
    private var statusDot: some View {
        if activity != nil || deviceOnline {
            Circle().fill(activity == .waiting ? Color.appNeedsYou : (activity != nil ? Color.appWorking : Color.appDone))
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
        }
    }

    private var visibleStatus: String? {
        if isIncognito { return "Not saved" }
        switch activity {
        case .listening: return "Listening"
        case .waiting: return "Needs you"
        case .working: return "Working"
        case nil: return nil
        }
    }
}
