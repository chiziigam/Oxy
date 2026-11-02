import SwiftUI

struct AdamConversationView: View {
    let initialMessage: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ChatViewModel()
    @State private var draft = ""
    @State private var voice = VoiceInputManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.adamBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Adam").font(.adamTitle).foregroundStyle(Color.adamInk)
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.adamLabel).foregroundStyle(Color.adamInk)
                        .frame(minWidth: AdamLayout.buttonHeight, minHeight: AdamLayout.buttonHeight)
                }
                .padding(.horizontal, AdamLayout.gutter)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    showsTypingIndicator: false,
                                    showsTimestamp: false,
                                    onActionCommand: { command in viewModel.sendCommand(command, userId: appState.userId) }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, AdamLayout.gutter)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last { withAnimation(reduceMotion ? nil : .appStandard) { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
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
