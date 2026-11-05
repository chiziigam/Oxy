import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Attachments

struct DSAttachment: Equatable {
    var data: Data
    var name: String
    var mime: String
    var isImage: Bool

    var preview: UIImage? { isImage ? UIImage(data: data) : nil }

    static func == (a: DSAttachment, b: DSAttachment) -> Bool {
        a.name == b.name && a.data.count == b.data.count
    }
}

@Observable
@MainActor
final class DSAttachments {
    var showSheet = false
    var showPhotos = false
    var showFiles = false
    var photoItem: PhotosPickerItem?
    var pending: DSAttachment?
}

/// Adds the attach sheet, the photo picker and the file picker to a screen.
struct DSAttachmentsModifier: ViewModifier {
    @Bindable var attachments: DSAttachments
    @Binding var draft: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $attachments.showSheet) {
                DSSheetBody(title: "Attach") {
                    VStack(spacing: 8) {
                        option("Photos", icon: .photo) { chain { attachments.showPhotos = true } }
                        option("File", icon: .doc) { chain { attachments.showFiles = true } }
                        option("Paste a link", icon: .link) {
                            attachments.showSheet = false
                            if let text = UIPasteboard.general.string, !text.isEmpty {
                                draft += (draft.isEmpty ? "" : " ") + text
                            }
                        }
                    }
                }
                .presentationDetents([.height(250)])
            }
            .photosPicker(isPresented: $attachments.showPhotos, selection: $attachments.photoItem, matching: .images)
            .fileImporter(isPresented: $attachments.showFiles, allowedContentTypes: [.pdf, .image, .plainText, .data], allowsMultipleSelection: false) { result in
                importFile(result)
            }
            .onChange(of: attachments.photoItem) { _, item in loadPhoto(item) }
    }

    private func option(_ title: String, icon: DSIcon, action: @escaping () -> Void) -> some View {
        Button {
            DSHaptics.light()
            action()
        } label: {
            HStack(spacing: 12) {
                DSIconView(icon: icon, size: 20)
                Text(title).font(.ds(15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(DS.ink)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: DS.Radius.item, style: .continuous).fill(DS.fill))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.item, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Close the sheet first, then open the picker, so the two presentations do not collide.
    private func chain(_ open: @escaping () -> Void) {
        attachments.showSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: open)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.jpegData(compressionQuality: 0.8) {
                attachments.pending = DSAttachment(data: jpeg, name: "photo.jpg", mime: "image/jpeg", isImage: true)
            }
            attachments.photoItem = nil
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let type = UTType(filenameExtension: url.pathExtension)
        attachments.pending = DSAttachment(
            data: data,
            name: url.lastPathComponent,
            mime: type?.preferredMIMEType ?? "application/octet-stream",
            isImage: type?.conforms(to: .image) ?? false
        )
    }
}

extension View {
    func dsAttachments(_ attachments: DSAttachments, draft: Binding<String>) -> some View {
        modifier(DSAttachmentsModifier(attachments: attachments, draft: draft))
    }

    /// Hands a finished voice transcript to the screen once.
    func dsVoice(_ voice: VoiceInputManager, onTranscript: @escaping (String) -> Void) -> some View {
        modifier(DSVoiceModifier(voice: voice, onTranscript: onTranscript))
    }
}

// MARK: - Voice

struct DSVoiceModifier: ViewModifier {
    var voice: VoiceInputManager
    var onTranscript: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: voice.isTranscribing) { _, now in if !now { deliver() } }
            .onChange(of: voice.transcript) { deliver() }
    }

    private func deliver() {
        guard !voice.isTranscribing else { return }
        let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        voice.transcript = ""
        onTranscript(text)
    }
}

// MARK: - Message box

struct DSComposer: View {
    @Binding var text: String
    var placeholder = "Message"
    var attachment: DSAttachment?
    var isBusy = false
    var voice: VoiceInputManager
    var onSend: () -> Void
    var onStop: () -> Void = {}
    var onAttach: () -> Void
    var onVoice: () -> Void
    var onRemoveAttachment: () -> Void = {}

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if let attachment { attachmentChip(attachment) }
            if voice.isRecording || voice.isTranscribing {
                listening
            } else {
                bar
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var bar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                focused = false
                onAttach()
            } label: {
                DSIconView(icon: .clip, size: 18)
                    .foregroundStyle(DS.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DS.card))
                    .overlay(Circle().strokeBorder(DS.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach")

            TextField(placeholder, text: $text, axis: .vertical)
                .font(.ds(14))
                .lineLimit(1...4)
                .focused($focused)
                .foregroundStyle(DS.ink)
                .tint(DS.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.card))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DS.line, lineWidth: 1))

            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isBusy {
            circle(.stop, label: "Stop") { onStop() }
        } else if canSend {
            circle(.send, label: "Send") {
                focused = false
                onSend()
            }
        } else {
            circle(.mic, label: "Speak") { onVoice() }
        }
    }

    private func circle(_ icon: DSIcon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSIconView(icon: icon, size: 18)
                .foregroundStyle(DS.accentInk)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var listening: some View {
        HStack(spacing: 12) {
            ZStack {
                Capsule().fill(DS.card)
                Capsule().strokeBorder(DS.line, lineWidth: 1)
                if voice.isTranscribing {
                    ProgressView().tint(DS.muted)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let level = voice.level()
                        HStack(spacing: 4) {
                            ForEach(0..<12, id: \.self) { i in
                                let wobble = 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.9)
                                Capsule().fill(DS.accent)
                                    .frame(width: 3, height: 6 + CGFloat(level * wobble) * 26)
                            }
                        }
                    }
                }
            }
            .frame(height: 44)
            .accessibilityLabel(voice.isTranscribing ? "Working on what you said" : "Listening")

            if voice.isRecording {
                circle(.stop, label: "Stop listening") { onVoice() }
            }
        }
    }

    private func attachmentChip(_ attachment: DSAttachment) -> some View {
        HStack {
            HStack(spacing: 8) {
                if let image = attachment.preview {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    DSIconView(icon: .doc, size: 18).frame(width: 32, height: 32)
                }
                Text(attachment.name).font(.ds(12.5)).lineLimit(1)
                Button(action: onRemoveAttachment) {
                    DSIconView(icon: .x, size: 14).foregroundStyle(DS.muted).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove attachment")
            }
            .foregroundStyle(DS.ink)
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.line, lineWidth: 1))
            Spacer(minLength: 0)
        }
    }
}
