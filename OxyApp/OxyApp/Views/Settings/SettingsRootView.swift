import SwiftUI

struct SettingsRootView: View {
    let onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var destination: Destination?
    @State private var showBackendURLEditor = false
    @State private var versionTapCount = 0
    @AppStorage("oxy_custom_backend_url") private var customBackendURL = ""

    private enum Destination: String, Identifiable {
        case devices, connections, payments, memory, you, account, sounds
        var id: String { rawValue }
    }

    private var soundsEnabled: Bool { UserDefaults.standard.bool(forKey: HouseholdSoundMonitor.preferenceKey) }

    var body: some View {
        ZStack {
            Color.adamBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Settings").font(.adamTitle).foregroundStyle(Color.adamInk)
                    Spacer()
                    Button("Done", action: onClose)
                        .font(.adamLabel).foregroundStyle(Color.adamInk)
                        .frame(minWidth: AdamLayout.buttonHeight, minHeight: AdamLayout.buttonHeight)
                }
                .padding(.horizontal, AdamLayout.gutter)
                ScrollView {
                    VStack(spacing: 0) {
                        row("Devices", .devices)
                        if soundsEnabled { row("Sounds heard", .sounds) }
                        row("Connections", .connections)
                        row("Payments", .payments)
                        row("Memory", .memory)
                        row("You", .you)
                        row("Account", .account)
                        Button {
                            versionTapCount += 1
                            if versionTapCount >= 5 { versionTapCount = 0; showBackendURLEditor = true }
                        } label: {
                            AdamMark().frame(width: 20, height: 20)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Adam")
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, AdamLayout.gutter)
                }
            }
        }
        .sheet(isPresented: $showBackendURLEditor) {
            BackendURLEditorSheet(currentURL: $customBackendURL) { showBackendURLEditor = false }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $destination) { item in
            destinationView(item).swipeToDismiss().environment(\.revealClose, nil).preferredColorScheme(.dark)
        }
        #if DEBUG
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["OXY_DEBUG_SETTINGS"], let target = Destination(rawValue: raw) {
                destination = target
            }
        }
        #endif
    }

    private func row(_ title: String, _ target: Destination) -> some View {
        VStack(spacing: 0) {
            Button { destination = target } label: {
                HStack {
                    Text(title).font(.adamTitle).foregroundStyle(Color.adamInk)
                    Spacer()
                    Image("ic-chevron-right").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 14, height: 14).foregroundStyle(Color.adamInk.opacity(0.6))
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Color.adamInk.opacity(0.15)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func destinationView(_ item: Destination) -> some View {
        switch item {
        case .devices: YourHomeView()
        case .sounds: SoundClipsPage()
        case .connections: ConnectorsView()
        case .payments: PaymentsView()
        case .memory: MemoryView()
        case .you: YouPage()
        case .account: ProfileView()
        }
    }
}
