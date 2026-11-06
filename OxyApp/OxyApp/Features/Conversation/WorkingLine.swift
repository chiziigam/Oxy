import SwiftUI

/// Shown while Adam works and has nothing to say yet: the steps it has really reported, as a short
/// trail. Finished steps get a check; the current one gets a small animation (they take turns on long work), its text decoding into place, and a timer once it is slow. Nothing here is guessed; with no step reported yet it
/// shows the animation alone.

/// Size of the graphic in points.
private let walkerSize: CGFloat = 18

struct WorkingLine: View {
    var steps: [ActivityStep] = []
    var label: String?
    /// Whether to add a "thinking" row when no step is in progress.
    var showsWaiting = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var since = Date()

    private struct Row: Identifiable {
        let id: String
        let title: String?
        let state: ActivityStepState
    }

    /// Words that say nothing ("Working on it") are not shown; the animation stands alone instead.
    private static let emptyWords: Set<String> = ["working on it", "thinking", "speaking"]

    private var usableLabel: String? {
        guard let label, !label.isEmpty, !Self.emptyWords.contains(label.lowercased()) else { return nil }
        return label
    }

    private var rows: [Row] {
        var result = steps.suffix(4).map { Row(id: $0.id.uuidString, title: $0.title, state: $0.state) }
        let hasActive = result.contains { $0.state == .active }
        if !hasActive, showsWaiting {
            if let label = usableLabel, result.isEmpty {
                result.append(Row(id: "label:\(label)", title: label, state: .active))
            } else {
                result.append(Row(id: "waiting", title: nil, state: .active))
            }
        }
        return result
    }

    var body: some View {
        let list = rows
        VStack(alignment: .leading, spacing: 8) {
            ForEach(list) { row in
                TrailRow(title: row.title, state: row.state, since: since)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: list.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.last(where: { $0.state == .active })?.title.map { "Adam is working: \($0)" } ?? "Adam is working")
    }
}

// MARK: - One step

private struct TrailRow: View {
    let title: String?
    let state: ActivityStepState
    let since: Date

    @State private var began = Date()

    var body: some View {
        HStack(spacing: 10) {
            indicator
                .frame(width: walkerSize, height: walkerSize)
            switch state {
            case .active:
                if let site = SiteTitle(title) {
                    SiteLabel(site: site, color: DS.ink)
                } else if let title {
                    DecodeText(text: title)
                }
                ElapsedTime(since: began)
            case .failed:
                if let site = SiteTitle(title) {
                    SiteLabel(site: site, color: DS.muted)
                } else {
                    Text(title ?? "")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(DS.muted)
                        .lineLimit(1)
                }
            default:
                if let site = SiteTitle(title) {
                    SiteLabel(site: site, color: DS.muted.opacity(0.75))
                } else {
                    Text(title ?? "")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(DS.muted.opacity(0.75))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: walkerSize)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .active, .pending:
            DSWorkingGraphic(since: since, size: walkerSize)
        case .failed:
            DSIconView(icon: .x, size: 13).foregroundStyle(DS.warn)
        default:
            DrawnCheck()
        }
    }
}

// MARK: - Pieces

/// A step like "Searching decathlon.co.uk" or "Reading target.com", split so the site can show its logo.
private struct SiteTitle {
    let verb: String
    let host: String

    init?(_ title: String?) {
        guard let title,
              let match = title.range(of: #"^(Searching|Reading) ((?:[a-z0-9-]+\.)+[a-z]{2,})$"#, options: [.regularExpression, .caseInsensitive]),
              match.lowerBound == title.startIndex else { return nil }
        let parts = title.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        verb = parts[0]
        host = parts[1].lowercased()
    }

    /// "decathlon.co.uk" -> "Decathlon", "www.target.com" -> "Target".
    var brand: String {
        var labels = host.split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        if labels.count > 1 { labels.removeLast() }
        if labels.count > 1, ["co", "com", "org", "ac", "gov"].contains(labels.last ?? "") { labels.removeLast() }
        return (labels.last ?? host).capitalized
    }

    var logoURL: URL? { URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") }
}

/// The verb, then the site's logo and name.
private struct SiteLabel: View {
    let site: SiteTitle
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(site.verb)
            AsyncImage(url: site.logoURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 15, height: 15)
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            Text(site.brand)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

/// A check that draws itself the first time it appears.
private struct DrawnCheck: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        DSIconShape(icon: .check)
            .trim(from: 0, to: progress)
            .stroke(DS.muted, style: StrokeStyle(lineWidth: 1.7 * 13 / 24, lineCap: .round, lineJoin: .round))
            .frame(width: 13, height: 13)
            .onAppear { withAnimation(.easeOut(duration: 0.32)) { progress = 1 } }
    }
}

/// Seconds spent on the current step, shown once it is clearly taking a while.
private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(since))
            if seconds >= 6 {
                Text("\(seconds)s")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(DS.muted.opacity(0.7))
                    .transition(.opacity)
            }
        }
    }
}

/// Text whose letters scramble and settle into place, left to right, whenever it changes.
private struct DecodeText: View {
    let text: String

    @State private var shown = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glyphs = Array("abcdefghijklmnopqrstuvwxyz0123456789#%&*+=/<>")

    var body: some View {
        Text(shown)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(DS.ink)
            .lineLimit(1)
            .task(id: text) { await decode() }
    }

    private func decode() async {
        if reduceMotion { shown = text; return }
        let letters = Array(text)
        let start = Date()
        while !Task.isCancelled {
            let progress = Date().timeIntervalSince(start) / 0.8
            if progress > 1.1 { break }
            shown = String(letters.enumerated().map { index, letter -> Character in
                if letter == " " { return " " }
                let settles = Double(index) / Double(max(letters.count, 1)) * 0.8
                return progress > settles + 0.2 ? letter : (Self.glyphs.randomElement() ?? letter)
            })
            try? await Task.sleep(for: .milliseconds(40))
        }
        if !Task.isCancelled { shown = text }
    }
}
