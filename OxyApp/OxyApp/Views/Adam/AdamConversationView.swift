import SwiftUI

struct AdamConversationView: View {
    let initialMessage: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = ChatViewModel()
    @State private var draft = ""
    @State private var voice = VoiceInputManager()
    @State private var showJumpToLatest = false

    private static let timeGap: TimeInterval = 15 * 60

    var body: some View {
        ZStack {
            Color.adamBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                transcript
                AskAdamBar(text: $draft, isRecording: voice.isRecording, onSend: send, onMic: toggleVoice)
            }
        }
        .task {
            await viewModel.loadHistory(userId: appState.userId)
            let first = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !first.isEmpty {
                viewModel.inputText = first
                viewModel.sendMessage(userId: appState.userId)
            }
        }
        .onChange(of: voice.isRecording) {
            if !voice.isRecording, !voice.transcript.isEmpty { draft = voice.transcript }
        }
    }

    private var header: some View {
        HStack {
            Text("Adam").font(.adamTitle).foregroundStyle(Color.adamInk)
            Spacer()
            Button("Close") { dismiss() }
                .font(.adamLabel).foregroundStyle(Color.adamInk)
                .frame(minWidth: AdamLayout.buttonHeight, minHeight: AdamLayout.buttonHeight)
        }
        .padding(.horizontal, AdamLayout.gutter)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            if showsSeparator(at: index) {
                                Text(separatorText(for: message.timestamp))
                                    .font(.adamLabel)
                                    .foregroundStyle(Color.adamMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 18)
                                    .padding(.bottom, 6)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            MessageBubble(
                                message: message,
                                showsTypingIndicator: false,
                                showsTimestamp: false,
                                onActionCommand: { command in viewModel.sendCommand(command, userId: appState.userId) }
                            )
                            .id(message.id)
                        }
                        if viewModel.isSending { workingRow }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                }
                .padding(.horizontal, AdamLayout.gutter)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: viewModel.isSending) {
                scrollToBottom(proxy, animated: true)
            }
        }
    }

    private static let bottomID = "adam-transcript-bottom"

    private var workingRow: some View {
        HStack(spacing: 8) {
            TypingDots()
            if let working {
                Text(working).font(.adamBody).foregroundStyle(Color.adamMuted)
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(working ?? "Adam is working")
    }

    private var working: String? {
        if let label = viewModel.statusLabel, !label.isEmpty { return label }
        if let step = viewModel.activitySteps.last(where: { $0.state == .active }) { return step.title }
        return nil
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask Adam anything").font(.adamTitle).foregroundStyle(Color.adamInk)
            Text("Bookings, forms, the house, your day.")
                .font(.adamBody).foregroundStyle(Color.adamMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 80)
    }

    private func showsSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = viewModel.messages[index].timestamp
        let previous = viewModel.messages[index - 1].timestamp
        return current.timeIntervalSince(previous) > Self.timeGap
    }

    private func separatorText(for date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return "\(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) \(time)"
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        withAnimation(animated && !reduceMotion ? .appStandard : nil) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        viewModel.inputText = text
        viewModel.sendMessage(userId: appState.userId)
    }

    private func toggleVoice() {
        if voice.isRecording { voice.stopRecording() } else { voice.startRecording(userId: appState.userId) }
    }
}

/// Three dots that lift in turn while Adam is working.
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.adamMuted)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .accessibilityHidden(true)
    }
}
