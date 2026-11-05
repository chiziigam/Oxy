import SwiftUI

/// The state of the home: what is wrong, if anything, then devices by room and recent events.
/// Everything here comes from the home loader; a group with nothing in it is not shown.
struct HomeScreen: View {
    @State private var home: HomeModel = .empty
    @State private var loaded = false
    @State private var failed = false
    @State private var showsSetup = false

    private var offline: [HomeModel.Device] { home.devices.filter { !$0.online } }

    private var stateTitle: String {
        switch offline.count {
        case 0: return "Nothing unusual"
        case 1: return "\(offline[0].name) is offline"
        default: return "\(offline.count) devices offline"
        }
    }

    private var lastEvent: String? {
        guard let latest = home.observations.first else { return nil }
        let time = Date.oxyParse(latest.at)?.formatted(date: .omitted, time: .shortened)
        return [time, latest.summary].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        DSScreen(title: "Home") {
            if failed {
                DSBanner(text: "Couldn't load your home.", actionTitle: "Retry") { Task { await load() } }
            }
            if loaded, !failed, home.devices.isEmpty {
                empty
            } else if !home.devices.isEmpty {
                state
                devices
                today
                watching
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsSetup) {
            PendantStatusView().presentationDetents([.large])
        }
    }

    private var state: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stateTitle)
                .font(.ds(26, .semibold))
                .tracking(-0.4)
                .foregroundStyle(offline.isEmpty ? DS.ink : DS.warn)
            if let lastEvent {
                Text("Last event \(lastEvent)").font(.ds(13)).foregroundStyle(DS.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var devices: some View {
        ForEach(home.rooms) { room in
            DSGroupCard(title: room.name) {
                ForEach(room.devices) { device in deviceRow(device) }
            }
        }
        if !home.unassignedDevices.isEmpty {
            DSGroupCard(title: home.rooms.isEmpty ? "Devices" : "Other devices") {
                ForEach(home.unassignedDevices) { device in deviceRow(device) }
            }
        }
    }

    private func deviceRow(_ device: HomeModel.Device) -> some View {
        DSItem(title: device.name, value: device.online ? "Online" : "Offline", warn: !device.online)
    }

    @ViewBuilder
    private var today: some View {
        let events = Array(home.observations.prefix(6))
        if !events.isEmpty {
            DSGroupCard(title: "Today") {
                ForEach(events) { event in
                    DSItem(title: event.summary, value: Date.oxyParse(event.at)?.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }

    @ViewBuilder
    private var watching: some View {
        if !home.watches.isEmpty {
            DSGroupCard(title: "Watching") {
                ForEach(home.watches) { watch in
                    DSItem(title: watch.title, subtitle: watch.detail)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            DSIconView(icon: .house, size: 30)
                .foregroundStyle(DS.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(DS.card))
                .overlay(Circle().strokeBorder(DS.line, lineWidth: 1))
            VStack(spacing: 4) {
                Text("No smart home devices").font(.ds(20, .semibold)).foregroundStyle(DS.ink)
                Text("Connect your speaker and devices to see them here.")
                    .font(.ds(13))
                    .foregroundStyle(DS.muted)
                    .multilineTextAlignment(.center)
            }
            Button("Connect") { showsSetup = true }.buttonStyle(.dsMid)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @MainActor
    private func load() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OXY_DEBUG_HOME"] == "sample" {
            home = .sample
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
}

#if DEBUG
extension HomeModel {
    /// Launch with OXY_DEBUG_HOME=sample to see the screen filled without a server.
    static let sample: HomeModel = {
        let speaker = Device(id: "d1", name: "Speaker", kind: "speaker", room: "Living room", online: true, lastSeenAt: nil)
        let plug = Device(id: "d2", name: "Plug", kind: "plug", room: "Living room", online: true, lastSeenAt: nil)
        let hallway = Device(id: "d3", name: "Plug", kind: "plug", room: "Hallway", online: false, lastSeenAt: nil)
        return HomeModel(
        presence: Presence(state: "home", homeConfigured: true),
        devices: [speaker, plug, hallway],
        rooms: [
            Room(name: "Living room", devices: [speaker, plug], active: true),
            Room(name: "Hallway", devices: [hallway], active: false)
        ],
        unassignedDevices: [],
        watches: [Watch(id: "w1", title: "Flight prices to Istanbul", detail: "Checks every Friday", nextRunAt: nil)],
        observations: [
            Observation(id: "o1", kind: "door", room: "Hallway", summary: "Front door opened", at: "2026-11-05T14:02:00Z", source: "sensor"),
            Observation(id: "o2", kind: "presence", room: "Study", summary: "Focus mode at your desk", at: "2026-11-05T09:15:00Z", source: "sensor")
        ]
        )
    }()
}
#endif
