import SwiftUI

// MARK: - Model

/// The current state of the home as Adam can know it (GET /agent/home). Devices, rooms, watches and
/// sensed events; conversation never appears here. Unknown stays unknown.
struct HomeModel: Codable, Equatable {
    struct Presence: Codable, Equatable {
        let state: String
        let homeConfigured: Bool
    }
    struct Device: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let name: String
        let kind: String
        let room: String?
        let online: Bool
        let lastSeenAt: String?
        var capabilities: [String]? = nil
        var showsUrgent: Bool { capabilities?.contains("urgent") == true }
    }
    struct Room: Codable, Equatable, Hashable, Identifiable {
        let name: String
        let devices: [Device]
        let active: Bool
        var id: String { name }
    }
    struct Watch: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let title: String
        let detail: String?
        let nextRunAt: String?
    }
    /// Something a device sensed or Adam inferred. Never a chat message or a reaction.
    struct Observation: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let kind: String
        let room: String?
        let summary: String
        let at: String
        let source: String
    }

    /// A smart-home device Adam can read and, where its capabilities say so, control
    /// (lights, switches, fans, climate; covers are read-only here). Unknown stays unknown.
    struct Control: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let name: String
        let room: String?
        let kind: String
        let state: String
        let available: Bool
        let isOn: Bool
        var brightness: Double? = nil
        var temperature: Double? = nil
        var targetTemperature: Double? = nil
        var minTemperature: Double? = nil
        var maxTemperature: Double? = nil
        var capabilities: [String]? = nil
        var updatedAt: String? = nil

        func can(_ capability: String) -> Bool { capabilities?.contains(capability) == true }
    }
    /// Where controls come from: "ok", "not_configured" (no smart-home server) or "unavailable".
    struct ControlSource: Codable, Equatable, Hashable {
        let status: String
        var detail: String? = nil
    }

    let presence: Presence
    let devices: [Device]
    let rooms: [Room]
    let unassignedDevices: [Device]
    let watches: [Watch]
    let observations: [Observation]
    var controls: [Control]? = nil
    var controlSource: ControlSource? = nil

    static let empty = HomeModel(
        presence: Presence(state: "unknown", homeConfigured: false),
        devices: [], rooms: [], unassignedDevices: [], watches: [], observations: []
    )
}

enum HomeService {
    /// Posted after a device changes from Home, so Now's summary can re-read the home.
    static let changedNotification = Notification.Name("AdamHomeChanged")

    static func fetch() async throws -> HomeModel {
        let data = try await APIClient.shared.request(path: "/agent/home")
        return try JSONDecoder().decode(HomeModel.self, from: data)
    }

    struct CommandResult: Decodable {
        let success: Bool
        var pending: Bool? = nil
        var error: String? = nil
        var control: HomeModel.Control? = nil
    }

    /// Sends one command from a device's control: on, off, toggle, brightness N or set N.
    /// The server runs it through Adam's action boundary and reads the device back.
    static func command(_ controlID: String, _ command: String) async throws -> CommandResult {
        let encoded = controlID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? controlID
        let data = try await APIClient.shared.request(path: "/agent/home/controls/\(encoded)", method: "POST", body: ["command": command])
        return try JSONDecoder().decode(CommandResult.self, from: data)
    }
}

/// Moves from something Adam knows to asking Adam about it: the thread picks this up as a draft.
@MainActor
enum AskAdam {
    static let notification = Notification.Name("AdamAskDraft")
    /// Unlike a draft, this sends the text straight away.
    static let sendNotification = Notification.Name("AdamAskSend")

    static func draft(_ text: String) {
        HapticManager.shared.impact(.light)
        NotificationCenter.default.post(name: notification, object: text)
    }
}

// MARK: - Your home

/// The home as a control screen: rooms as sections, each device a tile with its state and
/// one-tap controls where the device supports them. Unknown, unavailable and not configured
/// are always said plainly; nothing is drawn that a device did not report.
struct YourHomeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.revealClose) private var revealClose
    @State private var home: HomeModel = .empty
    @State private var settings = OxySettings()
    @State private var loaded = false
    @State private var failed = false
    @State private var isRefreshing = false
    @State private var showsDeviceSetup = false
    @State private var showsDisplaySetup = false
    @State private var selectedDevice: HomeModel.Device?
    @State private var showsSettings = false
    @State private var showsMap = false
    @State private var urgentChoice: [String: Bool] = [:]
    @State private var urgentErrors: [String: String] = [:]
    @State private var urgentPending: Set<String> = []
    /// Commands in flight, by control id, and the value shown while they run.
    @State private var pendingControls: Set<String> = []
    @State private var optimisticOn: [String: Bool] = [:]
    @State private var draftBrightness: [String: Double] = [:]
    @State private var controlErrors: [String: String] = [:]

    private var controls: [HomeModel.Control] { home.controls ?? [] }
    private var hasDevices: Bool { !home.devices.isEmpty || !controls.isEmpty }
    private var needsAddress: Bool { settings.homeLatitude == nil && settings.homeAddress.isEmpty }
    private var controlStatus: String { home.controlSource?.status ?? "not_configured" }

    /// Room names in a stable order: rooms with something on first, then by name.
    private var roomNames: [String] {
        let names = Set(home.devices.compactMap(\.room) + controls.compactMap(\.room))
        return names.sorted { a, b in
            let aOn = isAnythingOn(in: a), bOn = isAnythingOn(in: b)
            return aOn != bOn ? aOn : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    private func isAnythingOn(in room: String) -> Bool {
        home.devices.contains { $0.room == room && $0.online } || controls.contains { $0.room == room && $0.isOn }
    }

    private func tiles(in room: String?) -> [HomeTileItem] {
        home.devices.filter { $0.room == room }.map(HomeTileItem.display)
            + controls.filter { $0.room == room }.map(HomeTileItem.control)
    }

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: AppSpacing.md), GridItem(.flexible(), spacing: AppSpacing.md)]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeaderView(title: "Your home", onBack: revealClose == nil ? { dismiss() } : nil)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        if failed {
                            ErrorBanner(message: loaded && hasDevices ? "Couldn't refresh. Showing what was saved." : "Couldn't load your home.",
                                        onRetry: { Task { await load() } })
                                .disabled(isRefreshing)
                        }

                        if !loaded {
                            OxySkeletonCard(height: 24)
                            OxySkeletonCard(height: 132)
                            OxySkeletonCard(height: 132)
                        } else if hasDevices {
                            Text(summaryLine)
                                .font(.role(.body)).foregroundStyle(Color.appMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            controlSourceNotice
                            ForEach(roomNames, id: \.self) { room in
                                roomSection(room, tiles: tiles(in: room))
                            }
                            let loose = tiles(in: nil)
                            if !loose.isEmpty {
                                roomSection(roomNames.isEmpty ? "Devices" : "Not in a room", tiles: loose)
                            }
                            mapSection
                        } else if !failed {
                            notConnected
                        }

                        watchingSection
                        if hasDevices { noticedSection }
                        setUpSection
                    }
                    .padding(.horizontal, AppSpacing.margin)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable { await load() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await load()
            #if DEBUG
            if PreviewData.isIsolated, ProcessInfo.processInfo.environment["OXY_DEBUG_HOME_DETAIL"] == "1" {
                try? await Task.sleep(for: .milliseconds(700))
                selectedDevice = home.devices.first
            }
            #endif
        }
        // Devices also change from chat, voice and the devices themselves: re-read while this is open.
        .task(id: loaded) {
            guard loaded else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, pendingControls.isEmpty else { continue }
                await load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, loaded { Task { await load() } }
        }
        .sheet(item: $selectedDevice) { selected in
            if let device = home.devices.first(where: { $0.id == selected.id }) {
                deviceDetails(device)
            } else {
                SettingsPage(title: "Display") {
                    Text("This display is no longer available.")
                        .font(.role(.body)).foregroundStyle(Color.appMuted)
                }
            }
        }
        .sheet(isPresented: $showsDeviceSetup) {
            PendantStatusView().presentationDetents([.large])
        }
        .sheet(isPresented: $showsDisplaySetup) {
            PairedDisplaysView().presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showsSettings) {
            HomeAddressPage().swipeToDismiss()
        }
    }

    // MARK: Summary

    private var summaryLine: String {
        let presence: String
        switch home.presence.state {
        case "home" where home.presence.homeConfigured: presence = "You're home."
        case "away" where home.presence.homeConfigured: presence = "You're out."
        default: presence = "Location unknown."
        }
        return "\(HomeNowView.homeSummary(home)). \(presence)"
    }

    /// Smart-home control's own state, said once, above the rooms.
    @ViewBuilder
    private var controlSourceNotice: some View {
        if controlStatus == "unavailable" {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                StatusDot(color: .appNeedsYou)
                Text("Smart-home devices are unavailable right now. Their last state isn't shown.")
                    .font(.role(.footnote)).foregroundStyle(Color.appInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Rooms and tiles

    private func roomSection(_ title: String, tiles: [HomeTileItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.role(.callout, weight: .semibold)).foregroundStyle(Color.appInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AppSpacing.sm)
                Text(roomState(tiles)).font(.role(.footnote)).foregroundStyle(Color.appMuted)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.md) {
                ForEach(tiles) { tile in
                    switch tile {
                    case .display(let device): displayTile(device).id("home-device-\(device.id)")
                    case .control(let control): controlTile(control).id("home-control-\(control.id)")
                    }
                }
            }
        }
    }

    private func roomState(_ tiles: [HomeTileItem]) -> String {
        let on = tiles.filter { tile in
            switch tile {
            case .display(let device): return device.online
            case .control(let control): return isOn(control)
            }
        }.count
        if on == 0 { return "All off" }
        return on == tiles.count ? (tiles.count == 1 ? "On" : "All on") : "\(on) of \(tiles.count) on"
    }

    private func isOn(_ control: HomeModel.Control) -> Bool { optimisticOn[control.id] ?? control.isOn }

    private func icon(for control: HomeModel.Control) -> String {
        switch control.kind {
        case "light": return "bulb"
        case "fan": return "fan"
        case "climate": return "thermometer"
        case "cover": return "blinds"
        default: return "power"
        }
    }

    private func stateText(_ control: HomeModel.Control) -> String {
        guard control.available else { return control.state == "unavailable" ? "Unavailable" : "Unknown" }
        if pendingControls.contains(control.id) { return "Updating" }
        switch control.kind {
        case "climate":
            var parts: [String] = []
            if let now = control.temperature { parts.append("\(Self.degrees(now)) now") }
            if let target = control.targetTemperature { parts.append("set to \(Self.degrees(target))") }
            if control.state == "off" { parts.insert("Off", at: 0) }
            return parts.isEmpty ? control.state.capitalized : parts.joined(separator: " · ")
        case "cover":
            return control.state.capitalized
        default:
            guard isOn(control) else { return "Off" }
            if let level = draftBrightness[control.id] ?? control.brightness { return "On · \(Int(level.rounded()))%" }
            return "On"
        }
    }

    static func degrees(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))°" : String(format: "%.1f°", value)
    }

    private func tileIcon(_ name: String, on: Bool) -> some View {
        AppIcon(name, size: 18)
            .foregroundStyle(on ? Color.appAccent : Color.appMuted)
            .frame(width: 40, height: 40)
            .background(on ? Color.appAccentSoft : Color.appSurface2, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private func controlTile(_ control: HomeModel.Control) -> some View {
        let on = isOn(control)
        let busy = pendingControls.contains(control.id)
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .center) {
                tileIcon(icon(for: control), on: on && control.available)
                Spacer(minLength: AppSpacing.sm)
                if busy {
                    ProgressView().tint(Color.appMuted).frame(minWidth: 44, minHeight: 44)
                } else if control.can("toggle") {
                    SettingsToggle(isOn: Binding(
                        get: { isOn(control) },
                        set: { send(control, $0 ? "on" : "off", optimistic: $0) }
                    ))
                    .accessibilityLabel(control.name)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(control.name).font(.rowTitle).foregroundStyle(Color.appInk)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stateText(control)).font(.rowSecondary)
                    .foregroundStyle(control.available ? Color.appMuted : Color.appNeedsYou)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if control.can("brightness") && on && !busy {
                Slider(
                    value: Binding(
                        get: { draftBrightness[control.id] ?? control.brightness ?? 100 },
                        set: { draftBrightness[control.id] = $0 }
                    ),
                    in: 1...100,
                    step: 1,
                    onEditingChanged: { editing in
                        guard !editing, let level = draftBrightness[control.id] else { return }
                        send(control, "brightness \(Int(level.rounded()))", optimistic: true)
                    }
                )
                .tint(Color.appAccent)
                .accessibilityLabel("\(control.name) brightness")
                .accessibilityValue("\(Int((draftBrightness[control.id] ?? control.brightness ?? 100).rounded())) percent")
            }
            if control.can("temperature"), let target = control.targetTemperature, !busy {
                HStack(spacing: AppSpacing.sm) {
                    temperatureButton(control, target: target, step: -0.5)
                    Text(Self.degrees(target)).font(.reading(.callout, weight: .semibold)).foregroundStyle(Color.appInk)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    temperatureButton(control, target: target, step: 0.5)
                }
            }
            if control.kind == "cover" && control.available {
                Button("Ask Adam") {
                    AskAdam.draft("\(control.state == "open" ? "Close" : "Open") the \(control.name.lowercased())")
                }
                .buttonStyle(.app(.secondary, fullWidth: true))
                .accessibilityHint("Opens a draft in the conversation. Adam asks before opening or closing it.")
            }
            if let error = controlErrors[control.id] {
                Text(error).font(.role(.footnote)).foregroundStyle(Color.appDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .appCard(padding: AppSpacing.md)
    }

    private func temperatureButton(_ control: HomeModel.Control, target: Double, step: Double) -> some View {
        let next = min(control.maxTemperature ?? 30, max(control.minTemperature ?? 7, target + step))
        return Button {
            send(control, "set \(next)", optimistic: nil)
        } label: {
            AppIcon(step < 0 ? "minus" : "plus", size: 14)
        }
        .buttonStyle(.app(.secondary, fullWidth: false))
        .disabled(next == target)
        .accessibilityLabel(step < 0 ? "Lower \(control.name) to \(Self.degrees(next))" : "Raise \(control.name) to \(Self.degrees(next))")
    }

    private func displayTile(_ device: HomeModel.Device) -> some View {
        Button { selectedDevice = device } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    tileIcon("display", on: device.online && !failed)
                    Spacer(minLength: AppSpacing.sm)
                    AppIcon("chevron-right", size: 12).foregroundStyle(Color.appMuted).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.rowTitle).foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(displayState(device)).font(.rowSecondary).foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .appCard(padding: AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appScale(0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Display details")
    }

    private func displayState(_ device: HomeModel.Device) -> String {
        if failed { return device.online ? "Last reported online" : "Last reported offline" }
        return device.online ? "Online" : "Offline · \(lastSeen(device))"
    }

    // MARK: Commands

    private func send(_ control: HomeModel.Control, _ command: String, optimistic: Bool?) {
        guard !pendingControls.contains(control.id) else { return }
        HapticManager.shared.impact(.light)
        pendingControls.insert(control.id)
        controlErrors[control.id] = nil
        if let optimistic { optimisticOn[control.id] = optimistic }
        Task {
            defer {
                pendingControls.remove(control.id)
                optimisticOn[control.id] = nil
                draftBrightness[control.id] = nil
            }
            do {
                let result = try await HomeService.command(control.id, command)
                if let updated = result.control { replace(updated) }
                if result.pending == true {
                    controlErrors[control.id] = "Waiting for your approval in the conversation."
                } else if !result.success {
                    controlErrors[control.id] = result.error ?? "\(control.name) didn't confirm the change."
                    HapticManager.shared.error()
                } else {
                    HapticManager.shared.success()
                }
            } catch let APIError.server(status, message) where status < 500 && status != 401 {
                controlErrors[control.id] = message
                HapticManager.shared.error()
            } catch {
                controlErrors[control.id] = "Couldn't reach \(control.name). Nothing was changed."
                HapticManager.shared.error()
            }
            NotificationCenter.default.post(name: HomeService.changedNotification, object: nil)
        }
    }

    /// Puts the state the device reported after a command into the screen, nothing more.
    private func replace(_ control: HomeModel.Control) {
        guard var list = home.controls, let index = list.firstIndex(where: { $0.id == control.id }) else { return }
        list[index] = control
        home.controls = list
    }

    // MARK: Map

    /// The room map stays out of the way: a quiet disclosure, shown only when displays are placed in rooms.
    @ViewBuilder
    private var mapSection: some View {
        let mapRooms = HomeMap.rooms(from: home)
        if !home.devices.isEmpty && home.devices.contains(where: { $0.room != nil }) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Button {
                    withAnimation(.appStandard) { showsMap.toggle() }
                } label: {
                    HStack {
                        Text(showsMap ? "Hide room map" : "Show room map").font(.role(.callout, weight: .medium))
                            .foregroundStyle(Color.appInk)
                        Spacer()
                        AppIcon("chevron-down", size: 12).foregroundStyle(Color.appMuted)
                            .rotationEffect(.degrees(showsMap ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsMap ? "Shown" : "Hidden")
                if showsMap {
                    HomeMap(rooms: mapRooms, compact: true)
                        .appCard(padding: AppSpacing.sm)
                    Text("Drawn from the rooms you've named, not a measured plan.")
                        .font(.role(.caption)).foregroundStyle(Color.appMuted)
                }
            }
        }
    }

    // MARK: Not connected

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Nothing set up yet.")
                .font(.role(.title, weight: .bold)).foregroundStyle(Color.appInk)
            Text(controlStatus == "unavailable"
                 ? "Smart-home devices are unavailable right now. Pair a display, or try again later."
                 : "Pair a display, or connect a smart-home server, and each room shows here.")
                .font(.role(.body)).foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a display") {
                HapticManager.shared.impact(.medium)
                showsDisplaySetup = true
            }
            .buttonStyle(.appPrimary)
        }
    }

    // MARK: Watching, noticed, set up

    @ViewBuilder
    private var watchingSection: some View {
        if !home.watches.isEmpty {
            section("Watching") {
                ForEach(home.watches) { watch in
                    row(title: watch.title, detail: watch.detail ?? nextCheck(watch), dot: .appWorking) {
                        AskAdam.draft("What's happening with: \(watch.title)?")
                    }
                }
            }
        }
    }

    /// Only what a device sensed or Adam inferred. Empty until hardware reports something.
    @ViewBuilder
    private var noticedSection: some View {
        section("Noticed") {
            if home.observations.isEmpty {
                Text("Nothing reported by your devices yet.")
                    .font(.role(.footnote)).foregroundStyle(Color.appMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.sm)
            } else {
                ForEach(home.observations) { item in
                    row(title: item.summary, detail: observationDetail(item), dot: nil) {
                        AskAdam.draft("Tell me more about: \(item.summary)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var setUpSection: some View {
        if loaded {
            section("Set up") {
                row(title: "Add a display", detail: nil, dot: nil, chevron: true) { showsDisplaySetup = true }
                if controlStatus == "not_configured" {
                    row(title: "Smart-home control", detail: "Not configured", dot: nil, chevron: false) {
                        AskAdam.draft("How do I connect my smart-home devices?")
                    }
                }
                if needsAddress {
                    row(title: "Set your home location", detail: "For arrival and leaving reminders", dot: nil, chevron: true) {
                        showsSettings = true
                    }
                }
            }
        }
    }

    /// Urgent alerts are a choice made per screen: pairing a screen is not consent to put an alarm on it.
    private func deviceDetails(_ device: HomeModel.Device) -> some View {
        SettingsPage(title: device.name) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                tileIcon(device.kind == "browser" ? "display" : "cube", on: device.online && !failed)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(failed ? "Status unavailable" : (device.online ? "Online" : "Offline"))
                        .font(.role(.title, weight: .bold)).foregroundStyle(Color.appInk)
                    if let date = Date.oxyParse(device.lastSeenAt) {
                        Text("Last seen \(date.formatted(.relative(presentation: .named)))")
                            .font(.role(.callout)).foregroundStyle(Color.appMuted)
                    } else {
                        Text("Last seen unknown").font(.role(.callout)).foregroundStyle(Color.appMuted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .appCard()
            .accessibilityElement(children: .combine)
            SettingsList {
                SettingsRow(title: "Room", subtitle: device.room ?? "Not assigned")
                SettingsRule()
                SettingsRow(title: "Urgent alerts", subtitle: "Show alerts on this screen") {
                    SettingsToggle(isOn: Binding(
                        get: { urgentChoice[device.id] ?? device.showsUrgent },
                        set: { setUrgent(device, $0) }
                    ))
                    .disabled(failed || urgentPending.contains(device.id))
                    .accessibilityLabel("Urgent alerts on \(device.name)")
                }
                if urgentPending.contains(device.id) {
                    Text("Saving…").font(.role(.footnote)).foregroundStyle(Color.appMuted)
                        .padding(.bottom, 12)
                }
                if let error = urgentErrors[device.id] {
                    Text(error).font(.role(.footnote)).foregroundStyle(Color.appDanger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }
            }
            Button("Ask about this display") {
                selectedDevice = nil
                AskAdam.draft("How is the \(device.name) doing?")
            }
            .buttonStyle(.appSecondary)
            .accessibilityHint("Opens a draft in the conversation")
        }
        .refreshable { await load() }
    }

    private func setUrgent(_ device: HomeModel.Device, _ enabled: Bool) {
        guard !failed, !urgentPending.contains(device.id) else { return }
        let before = urgentChoice[device.id] ?? device.showsUrgent
        urgentChoice[device.id] = enabled
        urgentErrors[device.id] = nil
        urgentPending.insert(device.id)
        HapticManager.shared.impact(.light)
        Task {
            defer { urgentPending.remove(device.id) }
            do {
                let data = try await APIClient.shared.request(path: "/agent/displays/\(device.id)/urgent", method: "PUT", body: ["enabled": enabled])
                let result = try JSONDecoder().decode(UrgentPreferenceResponse.self, from: data)
                if result.id != device.id || result.urgent != enabled {
                    urgentChoice[device.id] = before
                    urgentErrors[device.id] = "Couldn't confirm alerts for \(device.name)."
                }
            } catch {
                urgentChoice[device.id] = before
                urgentErrors[device.id] = "Couldn't change alerts for \(device.name)."
            }
        }
    }

    private struct UrgentPreferenceResponse: Decodable {
        let id: String
        let urgent: Bool
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            AppSectionHeader(title: title)
            VStack(spacing: 0) { content() }
        }
    }

    private func row(title: String, detail: String?, dot: Color?, chevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                if let dot { StatusDot(color: dot, hollow: true) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rowTitle)
                        .foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.rowSecondary)
                            .foregroundStyle(Color.appMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                AppIcon(chevron ? "chevron-right" : "arrow-up-right", size: 12)
                    .foregroundStyle(Color.appMuted)
            }
            .padding(.vertical, AppSpacing.md)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Color.appHairline.frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.appScale(0.99))
    }

    // MARK: Formatting

    private func lastSeen(_ device: HomeModel.Device) -> String {
        guard let raw = device.lastSeenAt, let date = Date.oxyParse(raw) else { return "last seen unknown" }
        return "last seen \(date.formatted(.relative(presentation: .named)))"
    }

    private func nextCheck(_ watch: HomeModel.Watch) -> String? {
        guard let raw = watch.nextRunAt, let date = Date.oxyParse(raw), date > Date() else { return nil }
        return "Next check \(date.formatted(.relative(presentation: .named)))"
    }

    private func observationDetail(_ item: HomeModel.Observation) -> String {
        let when = Date.oxyParse(item.at).map { $0.formatted(.relative(presentation: .named)) } ?? ""
        let how: String
        switch item.source {
        case "sensor": how = "Sensed"
        case "inferred": how = "Inferred"
        default: how = "Reported"
        }
        return [item.room, how, when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Loading

    private func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if let data = UserDefaults.standard.data(forKey: "oxy_settings"),
           let saved = try? JSONDecoder().decode(OxySettings.self, from: data) {
            settings = saved
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if PreviewData.isIsolated, ["connected", "online", "offline", "unknown-seen", "cached-failure", "urgent-failure"].contains(env["OXY_DEBUG_HOME"] ?? "") {
            home = env["OXY_DEBUG_HOME"] == "offline" ? Self.sampleOffline : (env["OXY_DEBUG_HOME"] == "online" ? Self.sampleOnline : Self.sampleConnected)
            if env["OXY_DEBUG_HOME"] == "unknown-seen" {
                let device = HomeModel.Device(id: "unknown-seen", name: "Unassigned display", kind: "browser", room: nil, online: false, lastSeenAt: nil)
                home = HomeModel(presence: .init(state: "unknown", homeConfigured: false), devices: [device], rooms: [], unassignedDevices: [device], watches: [], observations: [])
            }
            loaded = true
            failed = env["OXY_DEBUG_HOME"] == "cached-failure"
            if env["OXY_DEBUG_HOME"] == "urgent-failure", let device = home.devices.first {
                setUrgent(device, true)
            }
            return
        }
        if PreviewData.isIsolated, env["OXY_DEBUG_HOME"] == "empty" {
            home = .empty
            loaded = true
            return
        }
        #endif
        do {
            home = try await HomeService.fetch()
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }

    #if DEBUG
    static let sampleConnected: HomeModel = {
        let seen = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30))
        let living = HomeModel.Device(id: "d1", name: "Living room display", kind: "browser", room: "Living room", online: true, lastSeenAt: seen)
        let kitchen = HomeModel.Device(id: "d2", name: "Kitchen display", kind: "browser", room: "Kitchen", online: false,
                                       lastSeenAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)))
        return HomeModel(
            presence: .init(state: "unknown", homeConfigured: false),
            devices: [living, kitchen],
            rooms: [.init(name: "Living room", devices: [living], active: true), .init(name: "Kitchen", devices: [kitchen], active: false)],
            unassignedDevices: [],
            watches: [.init(id: "w1", title: "Flight price check", detail: "Tell me when the price drops", nextRunAt: nil)],
            observations: [],
            controls: [
                HomeModel.Control(id: "light.living_room_lamp", name: "Lamp", room: "Living room", kind: "light", state: "on", available: true, isOn: true,
                      brightness: 60, capabilities: ["toggle", "brightness"]),
                HomeModel.Control(id: "switch.kettle", name: "Kettle", room: "Kitchen", kind: "switch", state: "off", available: true, isOn: false,
                      capabilities: ["toggle"]),
                HomeModel.Control(id: "climate.hall", name: "Heating", room: nil, kind: "climate", state: "heat", available: true, isOn: true,
                      temperature: 19.5, targetTemperature: 21, minTemperature: 7, maxTemperature: 30, capabilities: ["temperature"]),
                HomeModel.Control(id: "light.porch", name: "Porch light", room: nil, kind: "light", state: "unavailable", available: false, isOn: false)
            ],
            controlSource: HomeModel.ControlSource(status: "ok")
        )
    }()
    static var sampleOnline: HomeModel {
        let seen = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30))
        let devices = sampleConnected.devices.map { device in
            HomeModel.Device(id: device.id, name: device.name, kind: device.kind, room: device.room,
                online: true, lastSeenAt: seen, capabilities: device.capabilities)
        }
        return HomeModel(presence: .init(state: "unknown", homeConfigured: false), devices: devices,
            rooms: sampleConnected.rooms.map { room in .init(name: room.name, devices: devices.filter { $0.room == room.name }, active: true) },
            unassignedDevices: [], watches: sampleConnected.watches, observations: [])
    }
    static var sampleOffline: HomeModel {
        let seen = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let devices = sampleConnected.devices.map { device in
            HomeModel.Device(id: device.id, name: device.name, kind: device.kind, room: device.room,
                online: false, lastSeenAt: seen, capabilities: device.capabilities)
        }
        return HomeModel(presence: .init(state: "unknown", homeConfigured: false), devices: devices,
            rooms: sampleConnected.rooms.map { room in .init(name: room.name, devices: devices.filter { $0.room == room.name }, active: false) },
            unassignedDevices: [], watches: sampleConnected.watches, observations: [])
    }
    #endif
}

/// One tile on Your home: a paired display or a smart-home control.
enum HomeTileItem: Identifiable, Hashable {
    case display(HomeModel.Device)
    case control(HomeModel.Control)

    var id: String {
        switch self {
        case .display(let device): return "display-\(device.id)"
        case .control(let control): return "control-\(control.id)"
        }
    }
}
