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
        let all = (model.finished + model.board.completed).filter { seen.insert($0.id).inserted }
        return all.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Things Adam noticed but did not do: a delivery, a change at home. Not finished work.
    private var noticedItems: [BoardItem] {
        model.board.changed.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var doneLabel: String {
        doneItems.allSatisfy { $0.date.map(Calendar.current.isDateInToday) ?? false } ? "Done today" : "Done"
    }

    private var nothingToShow: Bool {
        model.needsYou.isEmpty && model.working.isEmpty && noticedItems.isEmpty && doneItems.isEmpty
    }

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
        .task {
            await model.refresh()
            #if DEBUG
            if PreviewData.isIsolated, ProcessInfo.processInfo.environment["OXY_DEBUG_CONVERSATION"] != nil {
                conversation = ConversationRequest(text: "")
            }
            #endif
        }
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
                    Text("Check your connection and try again.")
                        .font(.adamBody).foregroundStyle(Color.adamMuted)
                    AdamButton(title: "Try again", prominent: true) { Task { await model.refresh() } }
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
            if !noticedItems.isEmpty {
                sectionLabel("Noticed")
                ForEach(noticedItems) { item in
                    AdamDoneRow(item: item)
                }
            }
            if !doneItems.isEmpty {
                sectionLabel(doneLabel)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing needs you").font(.adamTitle).foregroundStyle(Color.adamInk)
            Text("Adam will tell you when something does.")
                .font(.adamBody).foregroundStyle(Color.adamMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
