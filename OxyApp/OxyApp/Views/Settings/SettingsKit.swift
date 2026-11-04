import SwiftUI

// MARK: - Store

/// Reads and writes the local settings blob, keeping the server's chat settings in step.
enum SettingsStore {
    static func load() -> OxySettings {
        var settings = OxySettings()
        if let data = UserDefaults.standard.data(forKey: "oxy_settings"),
           let saved = try? JSONDecoder().decode(OxySettings.self, from: data) {
            settings = saved
        }
        normalize(&settings)
        return settings
    }

    static func save(_ settings: OxySettings, userId: String) {
        var settings = settings
        normalize(&settings)
        UserDefaults.standard.set(settings.accentColor, forKey: "oxy_accentColor")
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "oxy_settings")
        }
        Task { await NativeIntegrationManager.shared.syncNativeContext(userId: userId) }
        Task {
            _ = try? await APIClient.shared.request(
                path: "/chat-settings",
                method: "PUT",
                body: ["effort": settings.chatEffort, "guardMode": settings.guardMode]
            )
        }
    }

    private static func normalize(_ settings: inout OxySettings) {
        settings.autonomy = OxySettings.normalizedAutonomy(settings.autonomy)
        if !OxySettings.accentOptions.contains(where: { $0.value == settings.accentColor }) {
            settings.accentColor = "stone"
        }
        settings.designPalette = settings.accentColor
    }
}

// MARK: - Surfaces and the dot

extension Color {
    /// A quiet lift above the page, in light and dark alike.
    static let settingsRaised = Color.appAdaptive(dark: .white.opacity(0.06), light: Color.appSurface)
}

extension View {
    /// The one grouped surface: compact radius, one hairline, no shadow.
    func settingsSurface(radius: CGFloat = 16) -> some View {
        self
            .background(Color.settingsRaised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.appHairline, lineWidth: 0.7))
    }
}

/// Adam's signature. A solid dot means Adam does this on its own; a ring means Adam asks you first.
struct AdamDot: View {
    var solid = true
    var size: CGFloat = 10

    var body: some View {
        Group {
            if solid {
                Circle().fill(Color.appAccent)
            } else {
                Circle().strokeBorder(Color.appAccent, lineWidth: max(1.5, size * 0.17))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Page scaffold

struct SettingsPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.revealClose) private var revealClose
    let title: String
    /// A screen opened straight from the menu button closes with that button's cross, so it shows no back arrow.
    var isRoot = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeaderView(title: title, onBack: isRoot && revealClose != nil ? nil : { dismiss() })
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) { content }
                        .padding(.horizontal, AdamLayout.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

/// A quiet label above a block of content.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.appBody(14, weight: .semibold))
                    .foregroundStyle(Color.appInk.opacity(0.62))
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
    }
}

/// Rows on one raised surface, separated by inset hairlines.
struct SettingsList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .settingsSurface()
    }
}

struct SettingsRule: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(Color.appHairline).frame(height: 0.5).padding(.leading, inset)
    }
}

// MARK: - Rows

enum SettingsLead {
    case icon(String)
    case dot(solid: Bool)
}

struct SettingsRow<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var subtitle: String? = nil
    var lead: SettingsLead? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button {
                HapticManager.shared.impact(.light)
                action()
            } label: { row }
                .buttonStyle(.appScale(0.99))
        } else {
            row
        }
    }

    private var row: some View {
        let stacked = typeSize.isAccessibilitySize && action == nil
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(alignment: .top, spacing: 12) {
                if let lead {
                    Group {
                        switch lead {
                        case .icon(let name):
                            AppIcon(name, size: 22)
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 32, height: 40)
                        case .dot(let solid): AdamDot(solid: solid, size: 10).frame(width: 22)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appBody(18, weight: .medium))
                        .foregroundStyle(Color.appInk)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appBody(14))
                            .foregroundStyle(Color.appMuted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trailing
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, lead: SettingsLead? = nil, action: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, lead: lead, action: action) { EmptyView() }
    }
}

struct SettingsNavRow: View {
    let title: String
    var subtitle: String? = nil
    var lead: SettingsLead? = nil
    let action: () -> Void

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, lead: lead, action: action) {
            AppIcon("chevron-right", size: 12).foregroundStyle(Color.appMuted)
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            SettingsToggle(isOn: $isOn)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
        }
    }
}

/// A sentence led by the dot. Used wherever the page states a plain fact about Adam.
struct SettingsStatement: View {
    let text: String
    var solid = true
    /// A fixed fact, not a state: shows an icon instead of an on/off dot.
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let icon {
                AppIcon(icon, size: 14)
                    .foregroundStyle(Color.appMuted)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
            } else {
                AdamDot(solid: solid, size: 10)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            }
            Text(text)
                .font(.appBody(16))
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

#if DEBUG
enum AgentContextDemo {
    static let snapshot = AgentContextSnapshot(
        agent: AgentIdentity(name: "Adam", role: "personal companion", continuity: "always here"),
        profile: AgentProfile(
            text: "",
            sections: [
                "identity": ["Based in Birmingham"],
                "work": ["Building Adam"],
                "relationships": ["Your supplier"],
                "goals": ["A calmer home and more time back"],
                "context": ["You prefer direct communication"]
            ]
        ),
        preferences: ["communication_style": "Direct"],
        memories: ["You prefer direct communication"],
        goals: [
            AgentContextGoal(id: "demo-watch", goal: "Flight prices to Turkey", status: "running", autonomy: "active", guardMode: false, currentStep: 1, updatedAt: nil)
        ],
        connectedApps: ["Gmail", "Calendar", "Reminders"],
        generatedAt: nil
    )
}
#endif
