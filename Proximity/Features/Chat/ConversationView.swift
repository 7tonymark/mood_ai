import SwiftUI

struct ConversationView: View {
    let friendID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showCamera = false
    @State private var viewing: AttachmentRef?
    @FocusState private var typing: Bool

    var body: some View {
        let friend = model.friend(friendID)
        let thread = model.messages(with: friendID)
        let color = friend?.color.color ?? Arcade.dim

        ArcadeScreen {
            header(friend, color: color)
            if friend == nil {
                Spacer()
                Text("THIS PLAYER IS NO LONGER ON YOUR LIST")
                    .font(Arcade.font(10))
                    .foregroundStyle(Arcade.red)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if thread.isEmpty {
                                Text("SAY HI. ONLY YOU TWO CAN READ THIS.")
                                    .font(Arcade.font(8))
                                    .foregroundStyle(Arcade.dim)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 40)
                            }
                            ForEach(thread) { message in
                                MessageBubble(
                                    message: message,
                                    isMine: message.from == model.myID,
                                    color: color,
                                    onPhoto: { viewing = $0 },
                                    onRetry: { model.retry(message.id) }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.trailing, 5)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { scrollToEnd(proxy, thread) }
                    .onChange(of: thread.count) {
                        scrollToEnd(proxy, thread)
                        model.markRead(friendID)
                    }
                }
                inputBar(color: color)
            }
        }
        .onAppear { model.markRead(friendID) }
        .onDisappear { model.markRead(friendID) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { model.sendMessage("", photo: $0, to: friendID) }
        }
        .fullScreenCover(item: $viewing) { PhotoViewer(ref: $0) }
    }

    private func header(_ friend: Friend?, color: Color) -> some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("<")
                    .font(Arcade.font(18))
                    .foregroundStyle(Arcade.yellow)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            if let friend {
                PixelAvatarView(avatar: friend.avatar, color: color, size: 28)
                Text(friend.name)
                    .font(Arcade.font(13))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private func inputBar(color: Color) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button("CAM") { showCamera = true }
                .buttonStyle(.arcade(Arcade.cyan, filled: false, size: 8))
                .frame(width: 64)
                .accessibilityLabel("Take a photo to send")
            TextField("", text: $draft, prompt: Text("Message").foregroundStyle(Arcade.dim), axis: .vertical)
                .font(Arcade.body(15))
                .foregroundStyle(Arcade.ink)
                .tint(color)
                .lineLimit(1...4)
                .focused($typing)
                .padding(10)
                .pixelPanel(color)
                .onChange(of: draft) {
                    if draft.count > AppModel.maxMessageLength {
                        draft = String(draft.prefix(AppModel.maxMessageLength))
                    }
                }
            Button("SEND") {
                model.sendMessage(draft, to: friendID)
                draft = ""
            }
            .buttonStyle(.arcade(Arcade.magenta, size: 8))
            .frame(width: 72)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.bottom, 6)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, _ thread: [ChatMessage]) {
        guard let last = thread.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    var isMine: Bool
    var color: Color
    var onPhoto: (AttachmentRef) -> Void
    var onRetry: () -> Void

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if let photo = message.photo {
                    Button { onPhoto(photo) } label: {
                        PhotoView(ref: photo)
                            .frame(width: 220)
                    }
                    .buttonStyle(.plain)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(Arcade.body(15))
                        .foregroundStyle(Arcade.ink)
                        .textSelection(.enabled)
                        .padding(10)
                        .pixelPanel(isMine ? Arcade.magenta : color, fill: isMine ? Arcade.magenta.opacity(0.15) : Arcade.panel)
                }
                HStack(spacing: 8) {
                    Text(Arcade.shortTime(message.sentAt))
                        .font(Arcade.font(7))
                        .foregroundStyle(Arcade.dim)
                    if isMine {
                        DeliveryLabel(status: message.status, onRetry: onRetry)
                    }
                }
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }
}
