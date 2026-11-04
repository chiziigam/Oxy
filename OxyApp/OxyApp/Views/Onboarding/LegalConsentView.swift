import SwiftUI

/// Consent gate.
struct LegalConsentView: View {
    var onContinue: () -> Void = {}

    @State private var agreedTerms = false
    @State private var agreedPrivacy = false

    private var canContinue: Bool { agreedTerms && agreedPrivacy }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                Text("Before you start")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.appInk)

                Text("Read how Adam handles your data, then agree to continue.")
                    .font(.body)
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                VStack(spacing: 0) {
                    consentRow(
                        isOn: $agreedTerms,
                        lead: "I agree to the",
                        emphasis: "Terms of Use"
                    )
                    consentRow(
                        isOn: $agreedPrivacy,
                        lead: "I have read the",
                        emphasis: "Privacy Policy"
                    )
                }
                .padding(.top, AppSpacing.xl)

                Spacer(minLength: 0)

                AppPrimaryButton(title: "Agree and continue", action: onContinue)
                    .disabled(!canContinue)
                    .animation(.appFast, value: canContinue)
            }
            .padding(.horizontal, 28)
            .padding(.top, 80)
            .padding(.bottom, 44)
        }
    }

    /// A native switch per agreement: the standard iOS control for an on/off choice.
    private func consentRow(isOn: Binding<Bool>, lead: String, emphasis: String) -> some View {
        Toggle(isOn: isOn.animation(.snappy)) {
            Text(lead + " ").foregroundColor(Color.appMuted) + Text(emphasis).foregroundColor(Color.appInk)
        }
        .font(.body)
        .tint(Color.appAccent)
        .frame(minHeight: 44)
        .padding(.vertical, AppSpacing.sm)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }
}

#Preview {
    LegalConsentView()
}
