import SwiftUI

/// A message being held: the message and where it is on screen.
struct HeldMessage {
    let message: Message
    let frame: CGRect
}

// MARK: - Swipe to reply, hold for reactions

/// Wraps one message: swipe right to reply, hold to react.
struct SwipeReplyRow<Content: View>: View {
    let message: Message
    var onReply: () -> Void
    var onHold: (CGRect) -> Void
    @ViewBuilder var content: Content

    @State private var dx: CGFloat = 0
    @State private var crossed = false
    @State private var frame: CGRect = .zero

    private let trigger: CGFloat = 46

    /// Cards that have their own buttons keep their taps and drags.
    private var mask: GestureMask {
        message.actions.contains { $0.scene?.spec?.mode == "interface" } ? .subviews : .all
    }

    var body: some View {
        content
            .offset(x: dx)
            .background(alignment: .leading) {
                DSIconView(icon: .back, size: 18)
                    .foregroundStyle(DS.muted)
                    .scaleEffect(0.6 + 0.4 * min(dx / trigger, 1))
                    .opacity(Double(min(dx / trigger, 1)))
                    .padding(.leading, DS.Space.edge)
                    .accessibilityHidden(true)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard value.translation.width > 0,
                              value.translation.width > abs(value.translation.height) * 1.4 else { return }
                        dx = min(value.translation.width * 0.55, 78)
                        if dx >= trigger, !crossed {
                            crossed = true
                            DSHaptics.light()
                        }
                    }
                    .onEnded { _ in
                        let fire = dx >= trigger
                        crossed = false
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { dx = 0 }
                        if fire { onReply() }
                    },
                including: mask
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    DSHaptics.light()
                    onHold(frame)
                },
                including: mask
            )
            .accessibilityAction(named: "Reply") { onReply() }
    }
}

// MARK: - Reaction badge

struct DSReactionBadge: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.system(size: 14))
            .padding(4)
            .background(Circle().fill(DS.card))
            .overlay(Circle().strokeBorder(DS.bg, lineWidth: 2))
            .accessibilityLabel("Reacted \(emoji)")
    }
}

// MARK: - Reply bar above the message box

struct DSReplyBar: View {
    let label: String
    let snippet: String
    var onTap: (() -> Void)?
    var onClose: () -> Void

    init(message: Message, onClose: @escaping () -> Void) {
        label = "Replying to \(message.role == .user ? "yourself" : "Adam")"
        snippet = ReplyQuote.snippet(of: message.content)
        onTap = nil
        self.onClose = onClose
    }

    init(label: String, snippet: String, onTap: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.label = label
        self.snippet = snippet
        self.onTap = onTap
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { onTap?() } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.ds(12, .medium))
                        .foregroundStyle(DS.muted)
                    Text(snippet)
                        .font(.ds(14))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            Button(action: onClose) {
                DSIconView(icon: .x, size: 14)
                    .foregroundStyle(DS.muted)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.card))
        .padding(.horizontal, DS.Space.edge)
        .padding(.top, 6)
    }
}

// MARK: - Picker shown when a message is held

struct DSReactionPicker: View {
    let held: HeldMessage
    let current: String?
    var onReact: (String) -> Void
    var onReply: () -> Void
    var onCopy: () -> Void
    var onClose: () -> Void

    @State private var shown = false
    @State private var showsMore = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUser: Bool { held.message.role == .user }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let top = max(held.frame.minY - origin.y - 66, DS.safeTop + 8)
            ZStack(alignment: .topLeading) {
                DS.bg.opacity(0.94)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Close")

                VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
                    HStack(spacing: 2) {
                        ForEach(ReactionStore.choices, id: \.self) { emoji in
                            emojiButton(emoji, size: 26)
                        }
                        Button {
                            DSHaptics.tick()
                            withAnimation(.smooth(duration: 0.22)) { showsMore.toggle() }
                        } label: {
                            DSIconView(icon: showsMore ? .x : .plus, size: 16)
                                .foregroundStyle(DS.ink)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(DS.fill))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showsMore ? "Fewer reactions" : "More reactions")
                    }
                    .padding(6)
                    .background(Capsule().fill(DS.card))

                    if showsMore {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 6), spacing: 2) {
                            ForEach(ReactionStore.more, id: \.self) { emoji in
                                emojiButton(emoji, size: 26)
                            }
                        }
                        .padding(10)
                        .frame(width: 300)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.card))
                        .transition(.scale(scale: 0.9, anchor: isUser ? .topTrailing : .topLeading).combined(with: .opacity))
                    } else {
                        Text(Self.preview(held.message))
                            .font(.ds(15))
                            .foregroundStyle(isUser ? DS.accentInk : DS.ink)
                            .lineLimit(6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(isUser ? DS.accent : DS.card))
                            .frame(maxWidth: proxy.size.width - 96, alignment: isUser ? .trailing : .leading)
                        HStack(spacing: 8) {
                            pill("Reply", action: onReply)
                            pill("Copy", action: onCopy)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.edge)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .offset(y: showsMore ? max(DS.safeTop + 8, min(top, proxy.size.height - 420)) : top)
                .scaleEffect(shown || reduceMotion ? 1 : 0.85, anchor: isUser ? .bottomTrailing : .bottomLeading)
                .opacity(shown || reduceMotion ? 1 : 0)
            }
        }
        .onAppear {
            if reduceMotion { shown = true; return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { shown = true }
        }
    }

    private static func preview(_ message: Message) -> String {
        ReplyQuote.split(message.content)?.body ?? message.content
    }

    private func emojiButton(_ emoji: String, size: CGFloat) -> some View {
        Button { onReact(emoji) } label: {
            Text(emoji)
                .font(.system(size: size))
                .frame(width: 44, height: 44)
                .background(Circle().fill(current == emoji ? DS.fill : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("React \(emoji)")
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ds(15, .medium))
                .foregroundStyle(DS.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Capsule().fill(DS.card))
        }
        .buttonStyle(.plain)
    }
}
