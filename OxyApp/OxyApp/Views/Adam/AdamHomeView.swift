import SwiftUI

private struct OpenWorkflow: Identifiable { let id: String }
private struct ConversationRequest: Identifiable { let id = UUID(); let text: String }

struct AdamHomeView: View {
    let onSettings: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = ThreadBoardModel()
    @State private var draft = ""
    @State private var conversation: ConversationRequest?
    @State private var openWorkflow: OpenWorkflow?
    @State private var showEarlier = false
    @State private var voice = VoiceInputManager()

    private static let visibleDone = 5

    private var doneItems: [BoardItem] {
        var seen = Set<String>()
        let all = (model.finished + model.board.changed + model.board.completed).filter { seen.insert($0.id).inserted }
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var doneToday: [BoardItem] {
        doneItems.filter { $0.date.map(Calendar.current.isDateInToday) ?? false }
    }

    private var nothingToShow: Bool { model.needsYou.isEmpty && model.working.isEmpty && doneItems.isEmpty }

    var body: some View {
        ZStack {
            Color.adamBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) { content }
                            .padding(.horizontal, AdamLayout.gutter)
                            .padding(.bottom, 24)
                    }
                    .refreshable { await model.refresh() }
                    .onReceive(NotificationCenter.default.publisher(for: .adamOpenItem)) { note in
                        guard let id = note.userInfo?["itemId"] as? String else { return }
                        Task {
                            await model.refresh()
                            let match = model.needsYou.first { $0.checkpointId == id || $0.workflowId == id || $0.id == id }
                            if let match { withAnimation(reduceMotion ? nil : .appStandard) { proxy.scrollTo(match.id, anchor: .top) } }
                        }
                    }
                }
                AskAdamBar(text: $draft, isRecording: voice.isRecording, onSend: send, onMic: toggleVoice)
            }
        }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.refresh() } } }
        .onChange(of: voice.isRecording) {
            if !voice.isRecording, !voice.transcript.isEmpty { draft = voice.transcript }
        }
        .sheet(item: $conversation) { request in
            AdamConversationView(initialMessage: request.text)
                .environment(appState)
        }
        .sheet(item: $openWorkflow) { open in
            WorkflowTimelineView(workflowId: open.id, onChanged: { Task { await model.refresh() } })
        }
        .onReceive(NotificationCenter.default.publisher(for: AskAdam.sendNotification)) { note in
            guard let text = note.object as? String else { return }
            openWorkflow = nil
            conversation = ConversationRequest(text: text)
        }
        .onReceive(NotificationCenter.default.publisher(for: AskAdam.notification)) { note in
            guard let text = note.object as? String else { return }
            openWorkflow = nil
            draft = text
        }
        .animation(reduceMotion ? nil : .appStandard, value: model.needsYou.map(\.id))
    }

    private var header: some View {
        HStack {
            Text("Adam").font(.adamTitle).foregroundStyle(Color.adamInk)
            Spacer()
            Button("Settings", action: onSettings)
                .font(.adamLabel)
                .foregroundStyle(Color.adamInk)
                .frame(minWidth: AdamLayout.buttonHeight, minHeight: AdamLayout.buttonHeight)
        }
        .padding(.horizontal, AdamLayout.gutter)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            ProgressView().tint(Color.adamInk).frame(maxWidth: .infinity).padding(.top, 60)
        } else if model.refreshFailed && nothingToShow {
            AdamCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn't load").font(.adamTitle).foregroundStyle(Color.adamInk)
                    AdamButton(title: "Retry", prominent: true) { Task { await model.refresh() } }
                }
            }
        } else if nothingToShow {
            emptyState
        } else {
            if !model.needsYou.isEmpty {
                sectionLabel("Needs you")
                ForEach(model.needsYou) { item in
                    AdamDecisionCard(item: item, model: model) { open(item) }.id(item.id)
                }
            }
            if !model.working.isEmpty {
                sectionLabel("Working")
                ForEach(model.working) { item in
                    AdamWorkingCard(item: item, model: model) { open(item) }
                }
            }
            if !doneItems.isEmpty {
                sectionLabel("Done today")
                ForEach(shownDone) { item in
                    AdamDoneRow(item: item) { open(item) }
                }
                if doneItems.count > Self.visibleDone {
                    Button(showEarlier ? "Show less" : "Earlier") { withAnimation(reduceMotion ? nil : .appStandard) { showEarlier.toggle() } }
                        .font(.adamLabel).foregroundStyle(Color.adamInk)
                        .frame(minHeight: AdamLayout.buttonHeight)
                }
            }
        }
    }

    private var shownDone: [BoardItem] {
        showEarlier ? doneItems : Array(doneItems.prefix(Self.visibleDone))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing needs you").font(.adamTitle).foregroundStyle(Color.adamInk)
            if !doneToday.isEmpty {
                Text(doneToday.count == 1 ? "Adam finished 1 thing today" : "Adam finished \(doneToday.count) things today")
                    .font(.adamBody).foregroundStyle(Color.adamInk.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.adamLabel).foregroundStyle(Color.adamInk).padding(.top, 8).padding(.leading, 4)
    }

    private func open(_ item: BoardItem) {
        model.markFinishedSeen(item)
        if let workflowId = item.workflowId { openWorkflow = OpenWorkflow(id: workflowId) }
        else { conversation = ConversationRequest(text: "") }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        conversation = ConversationRequest(text: text)
    }

    private func toggleVoice() {
        if voice.isRecording { voice.stopRecording() } else { voice.startRecording(userId: appState.userId) }
    }
}
