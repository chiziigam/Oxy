import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var showsSettings = false

    var body: some View {
        AdamHomeView(onSettings: { showsSettings = true })
            .tint(Color.adamAccent)
            .accessibilityHidden(showsSettings)
            .fullScreenCover(isPresented: $showsSettings) {
                SettingsRootView(onClose: { showsSettings = false })
                    .tint(Color.adamAccent)
            }
            .onReceive(NotificationCenter.default.publisher(for: AskAdam.sendNotification)) { _ in showsSettings = false }
            .onReceive(NotificationCenter.default.publisher(for: AskAdam.notification)) { _ in showsSettings = false }
            .onAppear { HapticManager.shared.prepare() }
    }
}

struct AdamPresence: View {
    enum PresenceState {
        case idle, listening, thinking, speaking, complete
    }

    var state: PresenceState = .idle
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var breathing = false
    @SwiftUI.State private var rotating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.appSurface)
                .shadow(color: Color.appAccent.opacity(0.12), radius: 22)

            Circle()
                .strokeBorder(Color.appHairline, lineWidth: 1)
                .padding(size * 0.08)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.42), Color.appAccent.opacity(0.08), .clear],
                        center: state == .listening ? .topLeading : .center,
                        startRadius: 2,
                        endRadius: size * 0.44
                    )
                )
                .padding(size * 0.13)
                .rotationEffect(.degrees(rotating ? 360 : 0))

            AdamMark()
                .frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (breathing ? activeScale : 1))
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: state == .idle ? 2.6 : 0.8).repeatForever(autoreverses: true),
            value: breathing
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .linear(duration: 6).repeatForever(autoreverses: false),
            value: rotating
        )
        .onAppear {
            breathing = true
            rotating = state == .thinking || state == .speaking
        }
        .onChange(of: state) { _, newState in
            rotating = newState == .thinking || newState == .speaking
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var activeScale: CGFloat {
        switch state {
        case .idle: return 1.018
        case .listening: return 1.05
        case .thinking, .speaking: return 1.025
        case .complete: return 0.98
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Adam is ready"
        case .listening: return "Adam is listening"
        case .thinking: return "Adam is thinking"
        case .speaking: return "Adam is speaking"
        case .complete: return "Adam finished"
        }
    }
}

// MARK: - More View

#Preview {
    MainTabView()
        .environment(AppState())
}
   

#if DEBUG
/// Debug only (OXY_DEBUG_YOU=indicator): the activity mark in each state, small and large.
struct ActivityMarkPreview: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 34) {
                ForEach([("Working", AdamActivityState.working), ("Listening", .listening), ("Waiting for you", .waiting)], id: \.0) { name, state in
                    HStack(spacing: 24) {
                        AdamActivityMark(state: state, size: 96)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(name).font(.appBody(15, weight: .medium)).foregroundStyle(Color.appInk)
                            AdamActivityMark(state: state, size: 28)
                        }
                    }
                }
                HStack(spacing: 24) {
                    TimelineView(.periodic(from: .now, by: 2.8)) { context in
                        let steps: [AdamActivityState] = [.working, .listening, .waiting]
                        AdamActivityMark(state: steps[Int(context.date.timeIntervalSinceReferenceDate / 2.8) % steps.count], size: 96)
                    }
                    Text("Changing state").font(.appBody(15, weight: .medium)).foregroundStyle(Color.appInk)
                }
                WorkingBubble(label: "Looking at image").padding(.horizontal, -AppSpacing.chatMargin)
            }
            .padding(.horizontal, AppSpacing.margin)
        }
    }
}
#endif

#if DEBUG
/// Debug only (OXY_DEBUG_YOU=transition): one large mark that goes working, then waiting, then back.
struct ActivityTransitionPreview: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 3.0)) { context in
                let working = Int(context.date.timeIntervalSinceReferenceDate / 3.0) % 2 == 0
                VStack(spacing: 28) {
                    AdamActivityMark(state: working ? .working : .waiting, size: 220)
                    Text(working ? "Working" : "Waiting for you")
                        .font(.appBody(17, weight: .medium))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
    }
}
#endif
