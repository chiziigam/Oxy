import SwiftUI

// MARK: - Reply quoting

/// A reply carries its quote as the first line of the message, so it survives history reloads,
/// reads naturally to Adam, and looks sensible in Telegram without any server change.
enum ReplyQuote {
    static let marker = "↩︎ "

    static func compose(quoting message: Message, body: String) -> String {
        let who = message.role == .user ? "You" : "Adam"
        return "\(marker)\(who): \(snippet(of: message.content))\n\n\(body)"
    }

    static func snippet(of content: String) -> String {
        let plain = (split(content)?.body ?? content)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.count > 80 ? String(plain.prefix(80)) + "…" : plain
    }

    static func split(_ content: String) -> (who: String, snippet: String, body: String)? {
        guard content.hasPrefix(marker), let end = content.range(of: "\n\n") else { return nil }
        let head = content[content.index(content.startIndex, offsetBy: marker.count)..<end.lowerBound]
        guard let colon = head.firstIndex(of: ":") else { return nil }
        let who = String(head[head.startIndex..<colon])
        let snippet = String(head[head.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        let body = String(content[end.upperBound...])
        return (who, snippet, body)
    }
}

// MARK: - Reactions

/// A tapped reaction travels to Adam as a message in this exact shape (matched on the server by
/// api/services/reactions.js). Neither it nor a "[quiet]" reply is ever drawn in the thread.
enum ReactionText {
    static let quietReply = "[quiet]"

    static func message(_ emoji: String, on message: Message) -> String {
        let quoted = ReplyQuote.snippet(of: message.content).replacingOccurrences(of: "”", with: "\"")
        return "Reacted \(emoji) to “\(quoted)”"
    }

    static func isReaction(_ content: String) -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Reacted ") && text.contains(" to “") && text.hasSuffix("”")
    }

    /// The emoji when Adam answered with a reaction instead of words: exactly `[react:EMOJI]`.
    static func agentReaction(_ content: String) -> String? {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("[react:"), text.hasSuffix("]") else { return nil }
        let emoji = String(text.dropFirst(7).dropLast())
        return !emoji.isEmpty && emoji.count <= 4 && !emoji.contains(" ") ? emoji : nil
    }

    /// True while a reaction is still arriving ("[re", "[react:👍"), so half a marker never flashes in a bubble.
    static func isAgentReactionInProgress(_ content: String) -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.count < 24 else { return false }
        if "[react:".hasPrefix(text) { return true }
        return text.hasPrefix("[react:") && !text.contains("]")
    }

    /// A reaction only stands in for words on a short, plain message. Anything that asked something is
    /// shown as the emoji on its own so the user is never left without an answer.
    static func canReact(to userContent: String) -> Bool {
        let text = (ReplyQuote.split(userContent)?.body ?? userContent).trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.contains("?") && text.split(whereSeparator: { $0.isWhitespace }).count <= 12
    }

    /// True for a quiet reply, including while it is still streaming in.
    static func isQuiet(_ content: String) -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !text.isEmpty && quietReply.hasPrefix(text) || text == quietReply
    }
}

/// One emoji per message, kept on this phone. A message that has not been saved yet is recorded
/// by what it says and when, then matched to its saved copy the next time history loads.
@MainActor
@Observable
final class ReactionStore {
    static let shared = ReactionStore()
    static let choices = ["❤️", "👍", "👎", "😂", "‼️", "❓"]
    static let more = [
        "🔥", "🙏", "👏", "🎉", "😍", "🥰", "😊", "😅", "🤣", "😭", "🥲", "😮",
        "😬", "🙄", "😴", "🤔", "🫡", "😎", "🤝", "💯", "✅", "❌", "👀", "💀",
        "🙌", "💪", "🫶", "😤", "🤯", "🥳", "😢", "😡", "🤷", "🫠", "⭐️", "💡"
    ]

    private struct Pending: Codable {
        var key: String
        var role: String
        var content: String
        var at: Date
    }

    private(set) var reactions: [String: String]
    private var pending: [Pending]

    private init() {
        let defaults = UserDefaults.standard
        reactions = (defaults.dictionary(forKey: "adam_reactions") as? [String: String]) ?? [:]
        pending = (defaults.data(forKey: "adam_reactions_pending"))
            .flatMap { try? JSONDecoder().decode([Pending].self, from: $0) } ?? []
    }

    private func key(for message: Message) -> String {
        message.dbId ?? "local-\(message.id.uuidString)"
    }

    func reaction(for message: Message) -> String? {
        reactions[key(for: message)]
    }

    /// Tapping the same emoji again removes it, like a tapback. Returns true when a reaction was added.
    @discardableResult
    func toggle(_ emoji: String, on message: Message) -> Bool {
        let id = key(for: message)
        let added = reactions[id] != emoji
        if !added {
            reactions[id] = nil
            pending.removeAll { $0.key == id }
        } else {
            reactions[id] = emoji
            if message.dbId == nil {
                pending.removeAll { $0.key == id }
                pending.append(Pending(key: id, role: message.role.rawValue,
                                       content: String(message.content.prefix(120)), at: message.timestamp))
            }
        }
        save()
        return added
    }

    func migrate(with messages: [Message]) {
        guard !pending.isEmpty else { return }
        var changed = false
        for item in pending {
            guard let dbId = savedID(matching: item, in: messages) else { continue }
            if let emoji = reactions.removeValue(forKey: item.key) { reactions[dbId] = emoji }
            pending.removeAll { $0.key == item.key }
            changed = true
        }
        if changed { save() }
    }

    private func savedID(matching item: Pending, in messages: [Message]) -> String? {
        for message in messages {
            guard let dbId = message.dbId, message.role.rawValue == item.role else { continue }
            guard String(message.content.prefix(120)) == item.content else { continue }
            if abs(message.timestamp.timeIntervalSince(item.at)) < 180 { return dbId }
        }
        return nil
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(reactions, forKey: "adam_reactions")
        defaults.set(try? JSONEncoder().encode(pending), forKey: "adam_reactions_pending")
    }
}

/// Shown while Adam works on a reply, as the dot at the left of the step being worked on, with no
/// bubble behind it. Only a real step is ever named; otherwise it is just the dot.

/// The reaction badge, pinned to the corner of the bubble itself.
struct ReactionBadge: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.appBody(15))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.appBackground))
            .overlay(Circle().strokeBorder(Color.appCardOutline, lineWidth: 1))
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Reacted \(emoji)")
    }
}
