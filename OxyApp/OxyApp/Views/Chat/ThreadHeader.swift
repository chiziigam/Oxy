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
    /// A standard back chevron, shown when this screen sits above another one.
    var onBack: (() -> Void)? = nil
    var backLabel: String = "Back"
    /// The greeting on Now and on an empty conversation; otherwise the request it is about.
    var title: String = "Adam"
    /// A large title for the greeting; an inline (headline) title for a conversation.
    var largeTitle: Bool = false
    /// The line under a large title, with its colour.
    var homeStatus: (text: String, color: Color)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var wheelOpen: Bool
    @Binding var hubCenter: CGPoint

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let onBack {
                Button {
                    HapticManager.shared.impact(.light)
                    onBack()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(backLabel)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(title)
                        .font(largeTitle ? .title2.weight(.bold) : .headline)
                        .foregroundStyle(Color.appInk)
                        .lineLimit(largeTitle && typeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.tail)
                        .accessibilityAddTraits(.isHeader)
                    if isDemo {
                        Text("Sample").font(.caption).foregroundStyle(Color.appMuted)
                    }
                }
                if let homeStatus, !isIncognito, largeTitle {
                    HStack(spacing: 7) {
                        Circle().fill(homeStatus.color).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(homeStatus.text).font(.footnote).foregroundStyle(Color.appMuted)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }
                    .accessibilityElement(children: .combine)
                } else if isIncognito {
                    Text("Not saved").font(.footnote).foregroundStyle(Color.appMuted)
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
            .accessibilityHint("Opens Now, Today, Activity, Memory, Your home and Settings")
            .accessibilityValue(isIncognito ? "Private mode on" : (visibleStatus ?? ""))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.leading, onBack == nil ? AppSpacing.chatMargin : AppSpacing.sm)
        .padding(.trailing, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .frame(minHeight: 52)
        .background(Color.appBackground.ignoresSafeArea(edges: .top))
        .animation(.appStandard, value: activity)
        .animation(.appStandard, value: deviceOnline)
    }

    @ViewBuilder
    private var statusDot: some View {
        if activity != nil || deviceOnline {
            Circle().fill(activity == .waiting ? Color.appNeedsYou : (activity != nil ? Color.appWorking : Color.appDone))
                .frame(width: 7, height: 7)
                .offset(x: -6, y: 8)
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
