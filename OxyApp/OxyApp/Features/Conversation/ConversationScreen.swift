import SwiftUI

/// The conversation on the main screen: history above, newest at the bottom.
struct ConversationThread: View {
    @Environment(AppState.self) private var appState

    var chat: ChatViewModel
    var topInset: CGFloat = 0
    var reactionVersion = 0
    var onReply: (Message) -> Void = { _ in }
    var onHold: (HeldMessage) -> Void = { _ in }

    @State private var didScrollToEnd = false

    private var visibleMessages: [Message] {
        chat.messages.filter { message in
            if message.role == .user { return !ReactionText.isReaction(message.content) }
            if ReactionText.isQuiet(message.content) || ReactionText.isAgentReactionInProgress(message.content) { return false }
            if ReactionText.agentReaction(message.content) != nil { return reactionTarget(of: message) == nil }
            // A reply to a reaction that failed or never came isn't worth showing.
            guard message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let index = chat.messages.firstIndex(where: { $0.id == message.id }), index > 0 else { return true }
            return !ReactionText.isReaction(chat.messages[index - 1].content)
        }
    }

    /// The message an emoji reaction from Adam lands on, or nil when it should show as a plain emoji.
    private func reactionTarget(of message: Message) -> Message? {
        guard let index = chat.messages.firstIndex(where: { $0.id == message.id }), index > 0 else { return nil }
        let target = chat.messages[index - 1]
        guard target.role == .user, !ReactionText.isReaction(target.content),
              ReactionText.canReact(to: target.content) else { return nil }
        return target
    }

    /// The emoji on a message: Adam's reaction to it, or the one chosen here.
    private func reaction(on message: Message) -> String? {
        _ = reactionVersion
        if message.role == .user,
           let index = chat.messages.firstIndex(where: { $0.id == message.id }),
           index + 1 < chat.messages.count {
            let next = chat.messages[index + 1]
            if next.role == .assistant, let emoji = ReactionText.agentReaction(next.content),
               reactionTarget(of: next)?.id == message.id { return emoji }
        }
        return ReactionStore.shared.reaction(for: message)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    if chat.hasOlderHistory, !visibleMessages.isEmpty {
                        ProgressView()
                            .tint(DS.muted)
                            .frame(height: 24)
                            .onAppear { loadOlder(proxy) }
                    }
                    ForEach(visibleMessages) { message in
                        SwipeReplyRow(
                            message: message,
                            onReply: { onReply(message) },
                            onHold: { onHold(HeldMessage(message: message, frame: $0)) }
                        ) {
                            bubble(message)
                        }
                        .id(message.id)
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
            .contentMargins(.top, topInset, for: .scrollContent)
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChange(of: visibleMessages.last?.id) {
                scrollToEnd(proxy, animated: didScrollToEnd)
                didScrollToEnd = true
            }
            .onChange(of: chat.messages.last?.content) { scrollToEnd(proxy, animated: true) }
        }
    }

    private func loadOlder(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            if let anchor = await chat.loadOlder(userId: appState.userId) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
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
                onSceneRequest: { chat.sendInterfaceRequest($0, userId: appState.userId) },
                reaction: reaction(on: message)
            )
        } else {
            assistantBubble(message)
        }
    }

    /// A reply to a message is stored as "↩︎ Name: quoted text", a blank line, then what was typed.
    /// The quote shows as a small muted line above the bubble instead of raw text with an arrow.
    private static func splitQuote(_ text: String) -> (quote: String?, body: String) {
        guard text.hasPrefix("↩︎ ") else { return (nil, text) }
        let parts = text.dropFirst(2).components(separatedBy: "\n\n")
        guard parts.count >= 2 else { return (nil, text) }
        var quote = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = quote.firstIndex(of: ":"), quote.distance(from: quote.startIndex, to: colon) <= 24 {
            quote = String(quote[quote.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let body = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (quote.isEmpty ? nil : quote, body)
    }

    private func userBubble(_ message: Message) -> some View {
        let split = Self.splitQuote(message.content)
        return HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                if let quote = split.quote {
                    Text(quote)
                        .font(.ds(13))
                        .foregroundStyle(DS.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.card))
                        .padding(.bottom, -2)
                }
                if let data = message.attachmentImage, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 160, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !split.body.isEmpty {
                    Text(split.body)
                        .font(.ds(15))
                        .foregroundStyle(DS.accentInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 5, topTrailingRadius: 18, style: .continuous).fill(DS.accent))
                        .overlay(alignment: .bottomLeading) { badge(for: message).offset(x: -8, y: 12) }
                }
            }
        }
    }

    private func assistantBubble(_ message: Message) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if message.content.isEmpty && message.isStreaming {
                    Text("…").font(.ds(15)).foregroundStyle(DS.muted)
                } else if !message.content.isEmpty {
                    Text(Self.attributed(message.content))
                        .font(.ds(15))
                        .foregroundStyle(DS.ink)
                }
                if let error = message.turnError {
                    Text(error).font(.ds(12.5)).foregroundStyle(DS.warn)
                    Button("Retry") { chat.retryLastFailedMessage(userId: appState.userId) }
                        .buttonStyle(.dsMidSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 5, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous).fill(DS.card))
            .overlay(alignment: .bottomTrailing) { badge(for: message).offset(x: 8, y: 12) }
            Spacer(minLength: 40)
        }
    }

    @ViewBuilder
    private func badge(for message: Message) -> some View {
        if let emoji = reaction(on: message) { DSReactionBadge(emoji: emoji) }
    }

    private static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
        } else {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }
}
