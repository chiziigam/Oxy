import SwiftUI

struct AdamCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AdamLayout.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.adamCard, in: RoundedRectangle(cornerRadius: AdamLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdamLayout.cardRadius, style: .continuous)
                    .strokeBorder(Color.adamCardEdge, lineWidth: 0.5)
            )
    }
}

struct AdamButton: View {
    let title: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.adamButton)
                .foregroundStyle(prominent ? Color.adamOnAccent : Color.adamInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: AdamLayout.buttonHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(prominent ? Color.adamAccent : Color.clear, in: RoundedRectangle(cornerRadius: AdamLayout.buttonRadius, style: .continuous))
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: AdamLayout.buttonRadius, style: .continuous)
                            .strokeBorder(Color.adamInk.opacity(0.28), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.appScale)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct AdamDecisionCard: View {
    let item: BoardItem
    let model: ThreadBoardModel
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isSent: Bool { model.submittingDecisions.contains(item.id) || model.acknowledged[item.id] != nil }

    var body: some View {
        AdamCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.adamTitle).foregroundStyle(Color.adamInk)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail).font(.adamBody).foregroundStyle(Color.adamMuted)
                    }
                }
                if let error = model.decisionErrors[item.id] {
                    Text(error).font(.adamBody).foregroundStyle(Color.adamInk)
                }
                if isSent {
                    Text("Sent").font(.adamBody).foregroundStyle(Color.adamMuted)
                } else {
                    buttons
                }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if item.hasDecision, let options = item.options, !options.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    AdamButton(title: option.label, prominent: index == 0) {
                        Task { await model.decide(item, approved: true, choice: option.id) }
                    }
                }
            }
        } else if item.hasDecision {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                AdamButton(title: "Approve", prominent: true) { Task { await model.decide(item, approved: true) } }
                AdamButton(title: "Decline") { Task { await model.decide(item, approved: false) } }
            }
        } else {
            AdamButton(title: "Open", prominent: true, action: onOpen)
        }
    }
}

struct AdamWorkingCard: View {
    let item: BoardItem
    let model: ThreadBoardModel
    let onOpen: () -> Void

    private var canStop: Bool { item.taskId != nil || item.canStop == true }
    private var detail: String? { item.stalled == true ? "Stuck" : item.detail }

    var body: some View {
        AdamCard {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.adamTitle).foregroundStyle(Color.adamInk)
                            .multilineTextAlignment(.leading)
                        if let detail, !detail.isEmpty {
                            Text(detail).font(.adamBody).foregroundStyle(Color.adamMuted)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(item.workflowId == nil)
                if let progress = item.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.adamTrack)
                            Capsule().fill(Color.adamAccent).frame(width: proxy.size.width * progress.fraction)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
                if canStop {
                    AdamButton(title: model.stopping.contains(item.id) ? "Stopping" : "Stop", isEnabled: !model.stopping.contains(item.id)) {
                        Task { await model.stop(item) }
                    }
                }
            }
        }
    }
}

struct AdamDoneRow: View {
    let item: BoardItem
    var onOpen: (() -> Void)? = nil

    var body: some View {
        if let onOpen {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.failed == true ? "Couldn't finish: \(item.title)" : item.title)
                .font(.adamBody).foregroundStyle(Color.adamInk)
            if let detail = item.detail, !detail.isEmpty {
                Text(detail).font(.adamLabel).foregroundStyle(Color.adamInk.opacity(0.7))
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: AdamLayout.buttonHeight, alignment: .leading)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
