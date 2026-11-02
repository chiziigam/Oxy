import SwiftUI
import UIKit

enum SetupState {
    static func isDone(_ userId: String) -> Bool { UserDefaults.standard.bool(forKey: "adam_setup_done_\(userId)") }
    static func markDone(_ userId: String) { UserDefaults.standard.set(true, forKey: "adam_setup_done_\(userId)") }
}

struct SetupFlowView: View {
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .name
    @State private var name = SettingsStore.load().userName
    @State private var googleConnected = false
    @State private var waitingForGoogle = false
    @State private var message: String?
    @State private var showsPairing = false
    @FocusState private var nameFocused: Bool

    private enum Step: Int, CaseIterable { case name, email, notifications, speaker }

    var body: some View {
        ZStack {
            Color.adamBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.adamLabel).foregroundStyle(Color.adamInk)
                    .padding(.top, 24)
                Spacer(minLength: 24)
                content
                    .id(step)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                Spacer()
                if let message {
                    Text(message).font(.adamBody).foregroundStyle(Color.adamInk).padding(.bottom, 12)
                }
                actions
            }
            .padding(.horizontal, AdamLayout.gutter + 8)
            .padding(.bottom, 16)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, waitingForGoogle { Task { await checkGoogle() } }
        }
        .sheet(isPresented: $showsPairing, onDismiss: finish) {
            PairedDisplaysView().presentationDetents([.large])
        }
        .task { await checkGoogle() }
    }

    private func heading(_ title: String, _ line: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.appBody(30, weight: .semibold)).foregroundStyle(Color.adamInk)
                .fixedSize(horizontal: false, vertical: true)
            if let line { Text(line).font(.adamBody).foregroundStyle(Color.adamInk.opacity(0.8)) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .name:
            VStack(alignment: .leading, spacing: 24) {
                heading("What should Adam call you?")
                TextField("", text: $name, prompt: Text("Your name").foregroundStyle(Color.adamMuted))
                    .font(.appBody(22, weight: .medium))
                    .foregroundStyle(Color.adamInk)
                    .textContentType(.givenName)
                    .submitLabel(.continue)
                    .focused($nameFocused)
                    .onSubmit { saveNameAndContinue() }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.adamInk.opacity(0.4)).frame(height: 1) }
            }
            .onAppear { nameFocused = true }
        case .email:
            VStack(alignment: .leading, spacing: 24) {
                heading("Connect your email and calendar", "So Adam can read replies and add events.")
                if googleConnected { Text("Connected").font(.adamTitle).foregroundStyle(Color.adamInk) }
            }
        case .notifications:
            heading("Turn on notifications", "Adam messages you when something needs you.")
        case .speaker:
            heading("Pair your speaker", "Adam listens and talks from the speaker at home.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            switch step {
            case .name:
                AdamButton(title: "Continue", prominent: true, action: saveNameAndContinue)
                skip("Skip") { advance() }
            case .email:
                if googleConnected {
                    AdamButton(title: "Continue", prominent: true) { advance() }
                } else {
                    AdamButton(title: waitingForGoogle ? "Check again" : "Connect Google", prominent: true) {
                        if waitingForGoogle { Task { await checkGoogle() } } else { Task { await connectGoogle() } }
                    }
                    skip("Not now") { advance() }
                }
            case .notifications:
                AdamButton(title: "Turn on", prominent: true) {
                    Task { @MainActor in
                        await NativeIntegrationManager.shared.requestNotificationPermission(userId: appState.userId)
                        advance()
                    }
                }
                skip("Not now") { advance() }
            case .speaker:
                AdamButton(title: "Pair speaker", prominent: true) { showsPairing = true }
                skip("I don't have one yet") { finish() }
            }
        }
    }

    private func skip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.adamButton).foregroundStyle(Color.adamInk)
                .frame(maxWidth: .infinity, minHeight: AdamLayout.buttonHeight)
        }
        .buttonStyle(.plain)
    }

    private func saveNameAndContinue() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var settings = SettingsStore.load()
            settings.userName = trimmed
            SettingsStore.save(settings, userId: appState.userId)
        }
        nameFocused = false
        advance()
    }

    private func advance() {
        message = nil
        guard let next = Step(rawValue: step.rawValue + 1) else { finish(); return }
        withAnimation(reduceMotion ? nil : .appStandard) { step = next }
    }

    private func finish() {
        SetupState.markDone(appState.userId)
        appState.startServices()
        onFinish()
    }

    private func connectGoogle() async {
        message = nil
        do {
            let data = try await APIClient.shared.request(path: "/auth/google/start", queryItems: [URLQueryItem(name: "userId", value: appState.userId)])
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["url"] as? String, let url = URL(string: text) else {
                message = "Couldn't open the sign-in page."
                return
            }
            waitingForGoogle = true
            await UIApplication.shared.open(url)
        } catch {
            message = "Couldn't connect Google. Try again."
        }
    }

    private func checkGoogle() async {
        guard let data = try? await APIClient.shared.request(path: "/connectors/\(appState.userId)"),
              let response = try? JSONDecoder().decode(ConnectorsResponse.self, from: data) else { return }
        let connected = response.connectors.contains { $0.id == "google" && $0.enabled }
        if connected { googleConnected = true; waitingForGoogle = false }
    }
}
