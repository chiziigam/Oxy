import SwiftUI

/// Pairing recovery.
struct ConnectionTroubleView: View {
    var onRetry: () -> Void = {}
    var onSkip: () -> Void = {}

    private let checks = [
        "Is it on its charger?",
        "Is Bluetooth on?",
        "Is it within a metre of your iPhone?"
    ]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                Text("Couldn't reach your home device")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.appInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                        checkRow(check)
                    }
                }
                .padding(.top, 40)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    AppPrimaryButton(title: "Try again", action: onRetry)
                    AppOutlineButton(title: "Skip for now", action: onSkip)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 80)
            .padding(.bottom, 44)
        }
    }

    private func checkRow(_ text: String) -> some View {
        HStack(spacing: 14) {
            Text("—")
                .font(.body)
                .foregroundStyle(Color.appMuted)
            Text(text)
                .font(.appBody(15, weight: .regular))
                .foregroundStyle(Color.appInk)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
    }
}

#Preview {
    ConnectionTroubleView()
}
