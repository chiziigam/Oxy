import SwiftUI

/// One task from the lists: what it is, anything waiting on you, and what has happened so far.
struct TaskScreen: View {
    let item: BoardItem
    var onChanged: () -> Void

    @State private var detail: WorkflowDetail?
    @State private var failed = false
    @State private var busy: String?
    @State private var errorText: String?

    var body: some View {
        DSScreen(title: item.title) {
            if let detail {
                content(detail)
            } else if item.workflowId == nil {
                DSGroupCard(title: "Details") {
                    DSItem(title: item.detail ?? "No more details")
                }
            } else if failed {
                DSBanner(text: "Couldn't load this.", actionTitle: "Retry") { Task { await load() } }
            } else {
                ProgressView().tint(DS.muted).padding(.top, 40)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ d: WorkflowDetail) -> some View {
        if d.pendingCheckpoints.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(d.workflow.plainStatus).font(.ds(22, .semibold)).tracking(-0.3).foregroundStyle(DS.ink)
                if let next = d.workflow.nextAction, !next.isEmpty {
                    Text(next).font(.ds(13)).foregroundStyle(DS.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let errorText { DSBanner(text: errorText) }

        ForEach(d.pendingCheckpoints) { checkpoint in
            DSGroupCard(title: "Needs you") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(checkpoint.prompt).font(.ds(14)).foregroundStyle(DS.ink)
                    HStack(spacing: 6) {
                        ForEach(Array((checkpoint.options ?? []).enumerated()), id: \.element.id) { index, option in
                            Button(option.label) { resolve(checkpoint, approved: true, choice: option.id) }
                                .buttonStyle(DSButtonStyle(kind: index == 0 ? .primary : .secondary, full: false))
                        }
                        if !checkpoint.isChoice {
                            Button("Approve") { resolve(checkpoint, approved: true, choice: nil) }
                                .buttonStyle(.dsMid)
                            Button("Decline") { resolve(checkpoint, approved: false, choice: nil) }
                                .buttonStyle(.dsMidSecondary)
                        }
                    }
                    .disabled(busy != nil)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }

        if !d.timeline.isEmpty {
            DSGroupCard(title: "So far") {
                ForEach(d.timeline) { event in
                    DSItem(
                        title: event.summary ?? event.kind.replacingOccurrences(of: "_", with: " ").capitalized,
                        value: event.date?.formatted(date: .omitted, time: .shortened)
                    )
                }
            }
        }

        if !d.documents.isEmpty {
            DSGroupCard(title: "Files") {
                ForEach(d.documents) { document in
                    DSItem(title: document.displayName, value: document.sizeText)
                }
            }
        }
    }

    private func resolve(_ checkpoint: WorkflowCheckpoint, approved: Bool, choice: String?) {
        guard let workflowId = item.workflowId else { return }
        busy = checkpoint.id
        errorText = nil
        Task { @MainActor in
            do {
                try await HomeBoardService.resolveCheckpoint(workflowId: workflowId, checkpointId: checkpoint.id, approved: approved, choice: choice)
                DSHaptics.success()
                onChanged()
                await load()
            } catch {
                DSHaptics.error()
                errorText = "Couldn't send that. Try again."
            }
            busy = nil
        }
    }

    @MainActor
    private func load() async {
        guard let id = item.workflowId else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["OXY_DEBUG_BOARD"] == "sample" {
            detail = .sample
            return
        }
        #endif
        do {
            detail = try await HomeBoardService.fetchWorkflow(id: id)
            failed = false
        } catch {
            failed = true
        }
    }
}

#if DEBUG
extension WorkflowDetail {
    static let sample = WorkflowDetail(
        workflow: WorkflowSummary(id: "w1", type: "order", goal: "Order groceries", status: "waiting_for_user", currentStep: nil,
                                  nextAction: "Waiting for your OK", deadline: nil, createdAt: nil, closedAt: nil),
        timeline: [
            WorkflowEvent(id: "e1", kind: "note", summary: "Checked three shops", actor: "agent", createdAt: "2026-11-05T09:50:00Z", refType: nil, refId: nil),
            WorkflowEvent(id: "e2", kind: "note", summary: "Built a basket of 12 items", actor: "agent", createdAt: "2026-11-05T09:52:00Z", refType: nil, refId: nil)
        ],
        pendingCheckpoints: [
            WorkflowCheckpoint(id: "c1", type: "approval_required", status: "pending", prompt: "Order 12 items for £48.20? Delivery Thursday, 6 to 8 pm.",
                               options: nil, expiresAt: nil)
        ],
        documents: []
    )
}
#endif
