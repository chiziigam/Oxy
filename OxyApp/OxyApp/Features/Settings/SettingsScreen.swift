import SwiftUI

/// Settings: Connections, You. Each setting appears once.
/// Pages that already work (accounts, cards, saved logins) open the existing screens
/// until they are restyled.
struct SettingsScreen: View {
    /// Existing pages that manage their own navigation, so they open full screen.
    private enum LegacyPage: String, Identifiable {
        case accounts, cards, logins, account
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var confirmSignOut = false
    @State private var legacy: LegacyPage?

    var body: some View {
        DSScreen(title: "Settings") {
            DSGroupCard(title: "Connections") {
                legacyRow("Accounts", page: .accounts)
                legacyRow("Cards", page: .cards)
                legacyRow("Saved logins", page: .logins)
            }
            DSGroupCard(title: "You") {
                link("Appearance", value: DSAppearance.shared.theme.title) { AppearanceScreen() }
                legacyRow("Account", page: .account, value: appState.userId)
                Button { confirmSignOut = true } label: {
                    DSItem(title: "Sign out")
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $confirmSignOut) {
            DSSheetBody(title: "Sign out?", message: "You will need to sign in again on this phone.") {
                VStack(spacing: 8) {
                    Button("Sign out") {
                        confirmSignOut = false
                        appState.logout()
                    }
                    .buttonStyle(.dsPrimary)
                    Button("Cancel") { confirmSignOut = false }
                        .buttonStyle(.dsSecondary)
                }
            }
            .presentationDetents([.height(260)])
        }
        .fullScreenCover(item: $legacy) { page in
            legacyDestination(page)
                .swipeToDismiss()
                .environment(\.revealClose, nil)
        }
    }

    private func legacyRow(_ title: String, page: LegacyPage, value: String? = nil) -> some View {
        Button { legacy = page } label: {
            DSItem(title: title, value: value, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func legacyDestination(_ page: LegacyPage) -> some View {
        switch page {
        case .accounts: ConnectorsView()
        case .cards: PaymentsView()
        case .logins: VaultView()
        case .account: ProfileView()
        }
    }

    private func link<Destination: View>(_ title: String, value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            DSItem(title: title, value: value, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}

/// Theme, accent colour and haptics. Nothing else is configurable on purpose.
struct AppearanceScreen: View {
    private var appearance: DSAppearance { DSAppearance.shared }

    var body: some View {
        DSScreen(title: "Appearance") {
            DSGroupCard(title: "Look") {
                DSItem(title: "Theme") {
                    HStack(spacing: 2) {
                        ForEach(DSTheme.allCases) { theme in
                            let selected = appearance.theme == theme
                            Button {
                                DSHaptics.tick()
                                appearance.choose(theme: theme)
                            } label: {
                                Text(theme.title)
                                    .font(.ds(12.5, .medium))
                                    .foregroundStyle(selected ? DS.accentInk : DS.muted)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? DS.accent : .clear))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                DSItem(title: "Accent") {
                    HStack(spacing: 6) {
                        ForEach(DSAccent.allCases) { accent in
                            let selected = appearance.accent == accent
                            Button {
                                DSHaptics.tick()
                                appearance.choose(accent: accent)
                            } label: {
                                Circle()
                                    .fill(DS.color(light: accent.light, dark: accent.dark))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(DS.ink, lineWidth: selected ? 2 : 0).padding(-3))
                                    .padding(3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.title)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
            DSGroupCard(title: "Feel") {
                DSItem(title: "Haptics") {
                    Toggle("Haptics", isOn: Binding(get: { appearance.haptics }, set: { appearance.setHaptics($0) }))
                        .labelsHidden()
                        .toggleStyle(DSToggleStyle())
                }
            }
        }
    }
}
