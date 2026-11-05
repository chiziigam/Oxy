import SwiftUI
import UIKit

// MARK: - Icons

struct DSIconView: View {
    let icon: DSIcon
    var size: CGFloat = 22

    var body: some View {
        DSIconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: size * 1.7 / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - Haptics (results and controls only, and only when switched on)

@MainActor
enum DSHaptics {
    private static var enabled: Bool { DSAppearance.shared.haptics }
    static func success() { if enabled { HapticManager.shared.success() } }
    static func warning() { if enabled { HapticManager.shared.warning() } }
    static func error() { if enabled { HapticManager.shared.error() } }
    static func tick() { if enabled { HapticManager.shared.select() } }
    static func light() { if enabled { HapticManager.shared.impact(.light) } }
}

// MARK: - Groups and chips

enum DSGroup: String, Hashable, CaseIterable {
    case needsYou, working, done

    var icon: DSIcon {
        switch self {
        case .needsYou: return .bell
        case .working: return .clock
        case .done: return .check
        }
    }

    var title: String {
        switch self {
        case .needsYou: return "Needs you"
        case .working: return "Working"
        case .done: return "Done"
        }
    }

    var spoken: String {
        switch self {
        case .needsYou: return "need you"
        case .working: return "working"
        case .done: return "done"
        }
    }
}

struct DSChip: View {
    let group: DSGroup
    let count: Int
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                DSIconView(icon: group.icon, size: 16)
                Text("\(count)").font(.ds(13, .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .foregroundStyle(isOn ? DS.accentInk : DS.muted)
            .background(Capsule().fill(isOn ? DS.accent : DS.card))
            .overlay(Capsule().strokeBorder(isOn ? DS.accent : DS.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(group.spoken)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct DSChipSkeleton: View {
    var body: some View {
        Capsule().fill(DS.line).frame(width: 56, height: 34)
    }
}

// MARK: - Buttons

struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, text, danger }

    var kind: Kind = .primary
    var full = true
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = compact ? 30 : (full ? 46 : 36)
        let radius: CGFloat = compact ? DS.Radius.small : (full ? DS.Radius.button : 10)
        configuration.label
            .font(.ds(compact ? 12.5 : (full ? 15 : 13), kind == .text ? .medium : .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, full ? 16 : 14)
            .frame(maxWidth: full ? .infinity : nil, minHeight: height)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(background))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return DS.accentInk
        case .secondary: return DS.ink
        case .text: return DS.muted
        case .danger: return .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return DS.accent
        case .secondary: return DS.card
        case .text: return .clear
        case .danger: return DS.danger
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return DS.accent
        case .secondary: return DS.line
        case .text: return .clear
        case .danger: return DS.danger
        }
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    static var dsPrimary: DSButtonStyle { DSButtonStyle(kind: .primary) }
    static var dsSecondary: DSButtonStyle { DSButtonStyle(kind: .secondary) }
    static var dsText: DSButtonStyle { DSButtonStyle(kind: .text) }
    static var dsDanger: DSButtonStyle { DSButtonStyle(kind: .danger) }
    static var dsMid: DSButtonStyle { DSButtonStyle(kind: .primary, full: false) }
    static var dsMidSecondary: DSButtonStyle { DSButtonStyle(kind: .secondary, full: false) }
    static var dsSmall: DSButtonStyle { DSButtonStyle(kind: .primary, full: false, compact: true) }
}

// MARK: - Cards and rows (one level of nesting: a group card with item rows inside)

struct DSGroupCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.ds(15, .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(DS.ink)
                    .padding(.leading, 8)
                    .padding(.top, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: DS.Space.rowGap) { content }
        }
        .padding(EdgeInsets(top: 12, leading: 6, bottom: 6, trailing: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
    }
}

struct DSItem<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var value: String?
    var showsChevron = false
    var danger = false
    var warn = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ds(14))
                    .foregroundStyle(danger ? DS.danger : DS.ink)
                if let subtitle {
                    Text(subtitle).font(.ds(12)).foregroundStyle(DS.muted)
                }
            }
            Spacer(minLength: 8)
            trailing
            if let value {
                Text(value)
                    .font(.ds(13.5))
                    .foregroundStyle(warn ? DS.warn : DS.muted)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                DSIconView(icon: .back, size: 12)
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(DS.muted)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, subtitle == nil ? 0 : 6)
        .frame(minHeight: subtitle == nil ? 40 : 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.item, style: .continuous).fill(DS.fill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.item, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

extension DSItem where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, value: String? = nil, showsChevron: Bool = false, danger: Bool = false, warn: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.showsChevron = showsChevron
        self.danger = danger
        self.warn = warn
        self.trailing = EmptyView()
    }
}

// MARK: - Banner

struct DSBanner: View {
    var text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            DSIconView(icon: .warn, size: 18).foregroundStyle(DS.warn)
            Text(text).font(.ds(13)).foregroundStyle(DS.ink).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(DSButtonStyle(kind: .secondary, full: false, compact: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
    }
}

// MARK: - Toggle

struct DSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            DSHaptics.tick()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? DS.accent : DS.line).frame(width: 44, height: 26)
                Circle().fill(Color.white).frame(width: 20, height: 20).padding(3)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
            .animation(.smooth(duration: 0.18), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

// MARK: - Screens

/// A pushed screen: back arrow and title in the same place every time.
struct DSScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Button { dismiss() } label: {
                        DSIconView(icon: .back, size: 20)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, -8)
                    .accessibilityLabel("Back")
                    Text(title)
                        .font(.ds(24, .semibold))
                        .tracking(-0.24)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.ink)
                .frame(height: 40)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) { content }
                        .padding(.bottom, 32)
                }
            }
            .padding(.horizontal, DS.Space.edge)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A bottom sheet body: title, one line of explanation, then the content.
struct DSSheetBody<Content: View>: View {
    var title: String
    var message: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.ds(17, .semibold)).foregroundStyle(DS.ink).padding(.top, 20)
            if let message {
                Text(message).font(.ds(13.5)).foregroundStyle(DS.muted)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.edge)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.card.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}

/// Keeps the edge-swipe back gesture working when the system navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
