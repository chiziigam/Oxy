import SwiftUI

enum DSRoute: Hashable {
    case home, settings
    case task(BoardItem)
}

private enum DecisionState: Equatable { case sending, failed }

/// The one screen after signing in: the conversation with its history, a message box, two chips for
/// open items, and two icons for Home and Settings. See DESIGN.md.
struct MainScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var path: [DSRoute] = []
    @State private var board = HomeBoard.empty
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var openGroup: DSGroup?
    @State private var chat = ChatViewModel()
    @State private var voice = VoiceInputManager()
    @State private var attachments = DSAttachments()
    @State private var draft = ""
    @State private var decisions: [String: DecisionState] = [:]
    @State private var replyingTo: Message?
    @State private var held: HeldMessage?
    @State private var reactionVersion = 0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DS.bg.ignoresSafeArea()
                ConversationThread(
                    chat: chat,
                    topInset: 56,
                    reactionVersion: reactionVersion,
                    onReply: startReply,
                    onHold: { held = $0 }
                )
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: DS.safeTop)
                            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 64)
                            Rectangle()
                        }
                    }
                if chat.messages.isEmpty, hasLoaded, !loadFailed {
                    Text("Ask for anything, or talk to the speaker.")
                        .font(.ds(13))
                        .foregroundStyle(DS.muted)
                }
            }
            .overlay(alignment: .top) {
                DS.bg.frame(height: DS.safeTop).ignoresSafeArea(edges: .top).allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    header
                    if loadFailed {
                        DSBanner(text: "No connection.", actionTitle: "Retry") { Task { await loadBoard() } }
                    }
                    if let message = voice.errorMessage {
                        DSBanner(text: message, actionTitle: "Dismiss") { voice.errorMessage = nil }
                    }
                    if let group = openGroup, !items(group).isEmpty {
                        panel(group)
                    }
                }
                .padding(.horizontal, DS.Space.edge)
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                if let replyingTo {
                    DSReplyBar(message: replyingTo) { withAnimation(.smooth(duration: 0.2)) { self.replyingTo = nil } }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                DSComposer(
                    text: $draft,
                    attachment: attachments.pending,
                    isBusy: chat.isSending,
                    voice: voice,
                    onSend: send,
                    onStop: { chat.stopCurrentTurn() },
                    onAttach: { attachments.showSheet = true },
                    onVoice: toggleVoice,
                    onRemoveAttachment: { attachments.pending = nil }
                )
                }
                .background(DS.bg.ignoresSafeArea(edges: .bottom))
            }
            .dsAttachments(attachments, draft: $draft)
            .dsVoice(voice) { text in
                draft = text
                send()
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if let held {
                    DSReactionPicker(
                        held: held,
                        current: ReactionStore.shared.reaction(for: held.message),
                        onReact: { react($0, on: held.message) },
                        onReply: { startReply(held.message) },
                        onCopy: {
                            UIPasteboard.general.string = ReplyQuote.split(held.message.content)?.body ?? held.message.content
                            DSHaptics.success()
                            self.held = nil
                        },
                        onClose: { self.held = nil }
                    )
                    .transition(.opacity)
                }
            }
            .navigationDestination(for: DSRoute.self) { route in
                switch route {
                case .home: HomeScreen()
                case .settings: SettingsScreen()
                case .task(let item): TaskScreen(item: item) { Task { await loadBoard() } }
                }
            }
        }
        .task { await chat.prepareChat(userId: appState.userId) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await loadBoard()
                try? await Task.sleep(for: .seconds(board.isWorking ? 8 : 25))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if !hasLoaded {
                    DSChipSkeleton(); DSChipSkeleton()
                } else {
                    ForEach(DSGroup.allCases, id: \.self) { group in
                        let list = items(group)
                        if !list.isEmpty {
                            DSChip(group: group, count: list.count, isOn: openGroup == group) { toggle(group) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                iconButton(.house, label: "Home") { path.append(.home) }
                iconButton(.sliders, label: "Settings") { path.append(.settings) }
            }
            .background(Capsule().fill(DS.card))
        }
        .frame(height: 36)
    }

    private func iconButton(_ icon: DSIcon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSIconView(icon: icon, size: 18)
                .foregroundStyle(DS.ink)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Lists

    private func items(_ group: DSGroup) -> [BoardItem] {
        switch group {
        case .needsYou:
            return board.needsYou
        case .working:
            return board.handling
        }
    }

    private func toggle(_ group: DSGroup) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.26)) {
            openGroup = (openGroup == group) ? nil : group
        }
    }

    private func panel(_ group: DSGroup) -> some View {
        let list = items(group)
        let rows = VStack(spacing: 0) {
            ForEach(list) { item in
                Rectangle().fill(DS.line).frame(height: 1)
                row(item, group: group)
            }
        }
        return VStack(spacing: 0) {
            Text(group.title)
                .font(.ds(13, .semibold))
                .foregroundStyle(DS.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 9)
            if list.count > 5 {
                ScrollView(showsIndicators: false) { rows }.frame(height: 360)
            } else {
                rows
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private func row(_ item: BoardItem, group: DSGroup) -> some View {
        let state = decisions[item.id]
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.ds(14, .semibold)).foregroundStyle(DS.ink).lineLimit(2)
                if state == .failed {
                    Text("Couldn't send that. Try again.").font(.ds(12.5)).foregroundStyle(DS.warn)
                } else if let detail = item.detail, !detail.isEmpty {
                    Text(detail).font(.ds(12.5)).foregroundStyle(DS.muted).lineLimit(2)
                }
                if group == .working, let progress = item.progress {
                    ProgressBar(fraction: progress.fraction)
                        .frame(width: 120)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 8)
            if group == .needsYou, item.hasDecision { decisionButton(item, state: state) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func decisionButton(_ item: BoardItem, state: DecisionState?) -> some View {
        let choice = item.options?.first
        return Button {
            decide(item, choice: choice)
        } label: {
            if state == .sending {
                ProgressView().tint(DS.accentInk).frame(minWidth: 40)
            } else {
                Text(choice?.label ?? "Approve").lineLimit(1)
            }
        }
        .buttonStyle(.dsSmall)
        .disabled(state == .sending)
    }

    private func open(_ item: BoardItem) {
        path.append(.task(item))
    }

    // MARK: Actions

    @MainActor
    private func loadBoard() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OXY_DEBUG_BOARD"] == "sample" {
            board = .sample
            hasLoaded = true
            loadFailed = false
            return
        }
        #endif
        do {
            board = try await HomeBoardService.fetchBoard()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        hasLoaded = true
    }

    private func decide(_ item: BoardItem, choice: BoardChoice?) {
        guard let workflowId = item.workflowId, let checkpointId = item.checkpointId else {
            open(item)
            return
        }
        decisions[item.id] = .sending
        Task { @MainActor in
            do {
                try await HomeBoardService.resolveCheckpoint(
                    workflowId: workflowId, checkpointId: checkpointId, approved: true, choice: choice?.id
                )
                DSHaptics.success()
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.25)) {
                    board = board.removing(item.id)
                    decisions[item.id] = nil
                }
                await loadBoard()
            } catch {
                DSHaptics.error()
                decisions[item.id] = .failed
            }
        }
    }

    private func toggleVoice() {
        guard !voice.isTranscribing else { return }
        if voice.isRecording {
            voice.stopRecording()
        } else {
            DSHaptics.light()
            voice.startRecording(userId: appState.userId)
        }
    }

    private func startReply(_ message: Message) {
        held = nil
        withAnimation(.smooth(duration: 0.2)) { replyingTo = message }
    }

    private func react(_ emoji: String, on message: Message) {
        if ReactionStore.shared.toggle(emoji, on: message) {
            chat.sendReaction(emoji, on: message, userId: appState.userId)
        }
        DSHaptics.tick()
        reactionVersion += 1
        held = nil
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachments.pending != nil else { return }
        let userId = appState.userId
        chat.inputText = text
        if let replyingTo, !text.isEmpty, attachments.pending == nil {
            chat.inputText = ReplyQuote.compose(quoting: replyingTo, body: text)
        }
        withAnimation(.smooth(duration: 0.2)) { replyingTo = nil }
        if let file = attachments.pending {
            chat.sendImageMessage(userId: userId, imageData: file.data, fileName: file.name, mimeType: file.mime, isImage: file.isImage)
            attachments.pending = nil
        } else {
            chat.sendMessage(userId: userId)
        }
        draft = ""
    }
}

// MARK: - Progress

struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.line)
                Capsule().fill(DS.accent).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Board helpers

extension HomeBoard {
    func removing(_ id: String) -> HomeBoard {
        HomeBoard(
            generatedAt: generatedAt, unavailableSources: unavailableSources, lastSeenAt: lastSeenAt,
            needsYou: needsYou.filter { $0.id != id }, handling: handling.filter { $0.id != id },
            changed: changed.filter { $0.id != id }, completed: completed.filter { $0.id != id },
            counts: counts
        )
    }
}

#if DEBUG
extension HomeBoard {
    /// Launch with OXY_DEBUG_BOARD=sample to see the screen filled without a server.
    static let sample = HomeBoard(
        generatedAt: nil, lastSeenAt: nil,
        needsYou: [
            BoardItem(id: "n1", kind: "checkpoint", title: "Order groceries", detail: "12 items, £48.20", at: nil,
                      workflowId: "w1", checkpointId: "c1", prompt: "Order 12 items for £48.20?",
                      options: [BoardChoice(id: "order", label: "Order £48.20", detail: nil)]),
            BoardItem(id: "n2", kind: "checkpoint", title: "Pay the council bill", detail: "£84.00, due 3 Nov", at: nil,
                      workflowId: "w2", checkpointId: "c2", prompt: "Pay £84.00?",
                      options: [BoardChoice(id: "pay", label: "Pay £84.00", detail: nil)])
        ],
        handling: [
            BoardItem(id: "h1", kind: "workflow", title: "Standing desks", detail: "3 of 6 shops checked", at: nil,
                      progress: BoardProgress(done: 3, total: 6))
        ],
        changed: [],
        completed: [
            BoardItem(id: "d1", kind: "workflow", title: "Train added to calendar", detail: "Yesterday", at: nil),
            BoardItem(id: "d2", kind: "workflow", title: "Bin day reminder", detail: "08:40", at: nil)
        ],
        counts: BoardCounts(needsYou: 2, handling: 1, changed: 0, completed: 2)
    )
}
#endif
