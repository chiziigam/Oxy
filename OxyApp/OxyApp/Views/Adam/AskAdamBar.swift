import SwiftUI

struct AskAdamBar: View {
    @Binding var text: String
    var isRecording = false
    let onSend: () -> Void
    let onMic: () -> Void

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask Adam", text: $text, axis: .vertical)
                .font(.adamBody)
                .foregroundStyle(Color.adamInk)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }
                .padding(.leading, 6)
            if canSend {
                Button(action: onSend) {
                    Image("ic-arrow-up").renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
                        .foregroundStyle(Color.adamOnAccent)
                        .frame(width: AdamLayout.buttonHeight - 8, height: AdamLayout.buttonHeight - 8)
                        .background(Color.adamAccent, in: Circle())
                }
                .accessibilityLabel("Send")
            } else {
                Button(action: onMic) {
                    Image(isRecording ? "ic-stop" : "ic-mic").renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
                        .foregroundStyle(Color.adamInk)
                        .frame(width: AdamLayout.buttonHeight - 8, height: AdamLayout.buttonHeight - 8)
                }
                .accessibilityLabel(isRecording ? "Stop recording" : "Speak")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: AdamLayout.buttonHeight + 8)
        .background(Color.adamCard, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.adamCardEdge, lineWidth: 0.5))
        .padding(.horizontal, AdamLayout.gutter)
        .padding(.bottom, 8)
    }
}
