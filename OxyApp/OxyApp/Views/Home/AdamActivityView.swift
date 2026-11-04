import SwiftUI

// MARK: - Model

/// What kind of thing an entry is. These are Adam's verbs; chat messages and reactions are none of them.
enum ActivityKind: String, Codable {
    case noticed, did, asked, scheduled, checked

    var label: String {
        switch self {
        case .noticed: return "Noticed"
        case .did: return "Did"
        case .asked: return "Asked you"
        case .scheduled: return "Scheduled"
        case .checked: return "Checked"
        }
    }
}

struct ActivityEvent: Codable, Identifiable, Equatable {
    let id: String
    let type: ActivityKind
    let title: String
    let detail: String?
    let at: String?
    let failed: Bool?
    let open: Bool?
    let stale: Bool?
    let workflowId: String?

    var date: Date? { at.flatMap(Date.oxyParse) }
    var isFailure: Bool { failed == true }
}

struct ActivityFeed: Codable, Equatable {
    let events: [ActivityEvent]
    let asks: [ActivityEvent]
    let upcoming: [ActivityEvent]

    static let empty = ActivityFeed(events: [], asks: [], upcoming: [])
}

enum ActivityService {
    static func fetch() async throws -> ActivityFeed {
        let data = try await APIClient.shared.request(path: "/agent/activity")
        return try JSONDecoder().decode(ActivityFeed.self, from: data)
    }
}

// MARK: - View

/// Adam's record of what it noticed, did, asked and scheduled. Conversation lives in Chat.
struct AdamActivityView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", done = "Done", comingUp = "Coming up"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var filter: Filter = .all
    @State private var feed: ActivityFeed = .empty
    @State private var isLoading = false
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var expandedID: String?
    @State private var openWorkflowID: String?

    private var asks: [ActivityEvent] { filter == .done ? [] : feed.asks }

    private var upcoming: [ActivityEvent] {
        filter == .done ? [] : feed.upcoming
    }

    private var past: [ActivityEvent] {
        switch filter {
        case .all: return feed.events
        case .done: return feed.events.filter { $0.type == .did && !$0.isFailure }
        case .comingUp: return []
        }
    }

    private var isEmpty: Bool { asks.isEmpty && upcoming.isEmpty && past.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeaderView(title: "Activity", onBack: { dismiss() })
            GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    filterBar

                    if !loaded && isLoading {
                        VStack(spacing: 16) {
                            OxySkeletonCard(height: 88, cornerRadius: 14)
                            OxySkeletonCard(height: 88, cornerRadius: 14)
                            OxySkeletonCard(height: 88, cornerRadius: 14)
                        }
                        .frame(width: max(0, geometry.size.width - AppSpacing.margin * 2))
                        .accessibilityLabel("Loading activity")
                    } else {
                        if let errorMessage {
                            ErrorBanner(message: errorMessage, onRetry: { Task { await load() } })
                                .disabled(isLoading)
                        }
                        if isEmpty && loaded && errorMessage == nil {
                            emptyState
                        } else {
                            if !asks.isEmpty { section("Needs you", asks) }
                            if !upcoming.isEmpty { section("Coming up", upcoming) }
                            ForEach(pastByDay) { day in
                                section(day.title, day.items)
                            }
                        }
                    }
                }
                .frame(width: max(0, geometry.size.width - AppSpacing.margin * 2), alignment: .leading)
                .padding(.horizontal, AppSpacing.margin)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable { await load() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await load()
            #if DEBUG
            if PreviewData.isIsolated, let state = ProcessInfo.processInfo.environment["OXY_DEBUG_ACTIVITY"] {
                switch state {
                case "refresh-failure": await load()
                case "expanded": expandedID = feed.asks.first?.id ?? feed.events.first?.id
                case "done": filter = .done
                case "coming-up": filter = .comingUp
                case "workflow":
                    try? await Task.sleep(for: .milliseconds(700))
                    openWorkflowID = "sample-workflow"
                default: break
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .fullScreenCover(item: Binding(
            get: { openWorkflowID.map(ActivityWorkflow.init) },
            set: { openWorkflowID = $0?.id }
        )) { workflow in
            WorkflowTimelineView(workflowId: workflow.id, onChanged: { Task { await load() } })
                .swipeToDismiss()
        }
    }

    // MARK: Pieces

    /// The system segmented control: one native picker for All, Done and Coming up.
    private var filterBar: some View {
        Picker("Show", selection: Binding(get: { filter }, set: { selectFilter($0) })) {
            ForEach(Filter.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func selectFilter(_ item: Filter) {
        guard filter != item else { return }
        withAnimation(reduceMotion ? nil : .appStandard) { filter = item }
    }

    /// Past entries grouped by day under one plain header each: Today, Yesterday, weekday, date.
    private struct DayGroup: Identifiable {
        let title: String
        var items: [ActivityEvent]
        var id: String { title }
    }

    private var pastByDay: [DayGroup] {
        var groups: [DayGroup] = []
        for item in past {
            let title = dayTitle(for: item.date)
            if let last = groups.indices.last, groups[last].title == title {
                groups[last].items.append(item)
            } else {
                groups.append(DayGroup(title: title, items: [item]))
            }
        }
        return groups
    }

    private func dayTitle(for date: Date?) -> String {
        guard let date else { return "Earlier" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide))
    }

    private func section(_ title: String, _ items: [ActivityEvent]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appMuted)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(items) { item in row(item) }
            }
        }
    }

    /// One plain row: what happened, one quiet line, the time at the end. Tap shows its actions.
    private func row(_ item: ActivityEvent) -> some View {
        let expanded = expandedID == item.id
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { expandedID = expanded ? nil : item.id }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(Color.appInk)
                            .lineLimit(expanded ? nil : 1)
                            .multilineTextAlignment(.leading)
                        if let detail = detailLine(for: item) {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(item.isFailure || item.type == .asked ? Color.appNeedsYou : Color.appMuted)
                                .lineLimit(expanded ? nil : 1)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: AppSpacing.sm)
                    Text(timeLabel(for: item))
                        .font(.footnote)
                        .foregroundStyle(Color.appMuted)
                        .accessibilityLabel(item.date == nil ? "Time unknown" : timeLabel(for: item))
                }
                .padding(.vertical, AppSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: expanded)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide actions")

            if expanded {
                HStack(spacing: AppSpacing.lg) {
                    if let workflowId = item.workflowId {
                        Button("View task") { openWorkflowID = workflowId }
                    }
                    Button("Ask about this") { AskAdam.draft("Tell me more about: \(item.title)") }
                        .accessibilityLabel("Ask about \(item.title)")
                        .accessibilityHint("Opens a draft in the conversation")
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .tint(Color.appAccent)
                .frame(minHeight: 44)
                .padding(.bottom, AppSpacing.sm)
                .transition(.opacity)
            }
        }
    }

    private func detailLine(for item: ActivityEvent) -> String? {
        if item.isFailure { return "Couldn't finish" }
        if item.type == .scheduled {
            if item.stale == true { return "Next check unknown" }
            return item.detail
        }
        guard let detail = item.detail, !detail.isEmpty,
              detail.caseInsensitiveCompare(item.title) != .orderedSame else { return nil }
        return detail
    }

    private func timeLabel(for item: ActivityEvent) -> String {
        guard let date = item.date else { return "Unknown" }
        let calendar = Calendar.current
        // Past rows sit under a day header, so the time alone is enough.
        if calendar.isDateInTomorrow(date) { return "Tomorrow " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(filter == .comingUp ? "Nothing scheduled" : (filter == .done ? "Nothing finished yet" : "No activity yet"))
                .font(.headline)
                .foregroundStyle(Color.appInk)
        }
        .padding(.top, 24)
    }

    // MARK: Loading

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if PreviewData.isIsolated, ProcessInfo.processInfo.environment["OXY_DEBUG_BOARD"] == "1" {
            feed = Self.sampleFeed
            errorMessage = nil
            loaded = true
            return
        }
        #endif
        do {
            let fetched = try await ActivityService.fetch()
            #if DEBUG
            if PreviewData.isIsolated, loaded,
               ProcessInfo.processInfo.environment["OXY_DEBUG_ACTIVITY"] == "refresh-failure" {
                feed = try JSONDecoder().decode(ActivityFeed.self, from: Data("{invalid isolated activity response".utf8))
            } else {
                feed = ProcessInfo.processInfo.environment["OXY_DEBUG_ACTIVITY"] == "unknown" && PreviewData.isIsolated
                    ? Self.unknownFeed : fetched
            }
            #else
            feed = fetched
            #endif
            errorMessage = nil
        } catch {
            errorMessage = feed == .empty ? "Couldn't load your activity" : "Couldn't refresh. Showing what was saved."
        }
        loaded = true
    }

    #if DEBUG
    private static let unknownFeed = ActivityFeed(events: [], asks: [
        ActivityEvent(id: "sample-unknown", type: .asked, title: "Review the delivery change", detail: "Waiting for your yes", at: nil, failed: false, open: true, stale: nil, workflowId: nil)
    ], upcoming: [
        ActivityEvent(id: "sample-stale", type: .scheduled, title: "Flight price check", detail: "Every Friday morning", at: nil, failed: false, open: nil, stale: true, workflowId: nil)
    ])

    private static let sampleFeed: ActivityFeed = {
        func iso(_ minutesAgo: Double) -> String {
            ISO8601DateFormatter().string(from: Date().addingTimeInterval(-minutesAgo * 60))
        }
        return ActivityFeed(
            events: [
                ActivityEvent(id: "e1", type: .did, title: "Sent a message to Arina", detail: nil, at: iso(12), failed: false, open: nil, stale: nil, workflowId: nil),
                ActivityEvent(id: "e2", type: .checked, title: "Looked up “AirPods case under £50”", detail: "No matching listing found", at: iso(40), failed: false, open: nil, stale: nil, workflowId: nil),
                ActivityEvent(id: "e3", type: .noticed, title: "Washing machine finished", detail: nil, at: iso(95), failed: false, open: nil, stale: nil, workflowId: nil)
            ],
            asks: [ActivityEvent(id: "a1", type: .asked, title: "Place the order, up to £60", detail: "Waiting for your yes", at: iso(3), failed: false, open: true, stale: nil, workflowId: nil)],
            upcoming: [
                ActivityEvent(id: "s1", type: .scheduled, title: "Remind you to leave for work", detail: "daily", at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(8 * 3600)), failed: false, open: nil, stale: false, workflowId: nil),
                ActivityEvent(id: "s2", type: .scheduled, title: "Bin day", detail: "weekly", at: nil, failed: false, open: nil, stale: true, workflowId: nil)
            ]
        )
    }()
    #endif
}

private struct ActivityWorkflow: Identifiable { let id: String }
