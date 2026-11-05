import SwiftUI

/// One conversation. The header and message box are frosted over the thread.
struct ConversationScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var chat: ChatViewModel

    @State private var voice = VoiceInputManager()
    @State private var attachments = DSAttachments()
    @State private var draft = ""

    private var visibleMessages: [Message] {
        chat.messages.filter { message in
            let text = message.content
            if text.hasPrefix("[quiet") || text.hasPrefix("[react:") { return false }
            if message.role == .user, text.hasPrefix("Reacted ") { return false }
            return true
        }
    }

    private var title: String {
        let first = chat.messages.first(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Conversation"
        return first.count > 28 ? String(first.prefix(28)) + "…" : first
    }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleMessages) { message in
                            bubble(message).id(message.id)
                        }
                        if chat.isSending, let status = chat.statusLabel, !status.isEmpty {
                            Text(status)
                                .font(.ds(12.5))
                                .foregroundStyle(DS.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, DS.Space.edge)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: chat.messages.count) { scrollToEnd(proxy) }
                .onChange(of: chat.messages.last?.content) { scrollToEnd(proxy) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .dsAttachments(attachments, draft: $draft)
        .dsVoice(voice) { text in
            draft = text
            send()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Frosted bars

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                DSIconView(icon: .back, size: 20)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -8)
            .accessibilityLabel("Back")
            Text(title).font(.ds(24, .semibold)).tracking(-0.24).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.ink)
        .padding(.horizontal, DS.Space.edge)
        .frame(height: 48)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: 1) }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let message = voice.errorMessage {
                DSBanner(text: message, actionTitle: "Dismiss") { voice.errorMessage = nil }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            DSComposer(
                text: $draft,
                placeholder: "Reply",
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
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }

    // MARK: Messages

    @ViewBuilder
    private func bubble(_ message: Message) -> some View {
        if message.role == .user {
            userBubble(message)
        } else if !message.actions.isEmpty || !message.sources.isEmpty || message.offer != nil {
            // Rich results (confirmations, places, travel) keep their full cards.
            MessageBubble(
                message: message,
                onActionCommand: { chat.sendCommand($0, userId: appState.userId) },
                onRetryFailedTurn: { chat.retryLastFailedMessage(userId: appState.userId) },
                onSceneRequest: { chat.sendInterfaceRequest($0, userId: appState.userId) }
            )
        } else {
            assistantBubble(message)
        }
    }

    private func userBubble(_ message: Message) -> some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                if let data = message.attachmentImage, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 160, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.ds(14))
                        .foregroundStyle(DS.accentInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16, style: .continuous).fill(DS.accent))
                }
            }
        }
    }

    private func assistantBubble(_ message: Message) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if message.content.isEmpty && message.isStreaming {
                    Text("…").font(.ds(14)).foregroundStyle(DS.muted)
                } else if !message.content.isEmpty {
                    Text(Self.attributed(message.content))
                        .font(.ds(14))
                        .foregroundStyle(DS.ink)
                }
                if let error = message.turnError {
                    Text(error).font(.ds(12.5)).foregroundStyle(DS.warn)
                    Button("Retry") { chat.retryLastFailedMessage(userId: appState.userId) }
                        .buttonStyle(.dsMidSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous).fill(DS.card))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
            Spacer(minLength: 48)
        }
    }

    private static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    // MARK: Actions

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
        } else {
            proxy.scrollTo("end", anchor: .bottom)
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

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachments.pending != nil else { return }
        chat.inputText = text
        if let file = attachments.pending {
            chat.sendImageMessage(userId: appState.userId, imageData: file.data, fileName: file.name, mimeType: file.mime, isImage: file.isImage)
            attachments.pending = nil
        } else {
            chat.sendMessage(userId: appState.userId)
        }
        draft = ""
    }
}
