import SwiftUI

struct FeedView: View {
    @Environment(AppModel.self) private var model
    @State private var composing = false
    @State private var viewing: AttachmentRef?
    @State private var pendingDelete: FeedPost?

    var body: some View {
        VStack(spacing: 12) {
            Button("+ NEW POST") { composing = true }
                .buttonStyle(.arcade(Arcade.green, size: 11))

            if model.feed.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(model.feed) { post in
                            PostCard(
                                post: post,
                                author: model.card(for: post.author),
                                isMine: post.author == model.myID,
                                onPhoto: { viewing = $0 },
                                onRetry: { model.retry(post.id) }
                            )
                            .contextMenu {
                                if post.author == model.myID {
                                    Button("Delete post", systemImage: "trash", role: .destructive) { pendingDelete = post }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.trailing, 5) // room for the panel shadows
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.sync(full: true) }
            }
        }
        .fullScreenCover(isPresented: $composing) { ComposePostView() }
        .fullScreenCover(item: $viewing) { PhotoViewer(ref: $0) }
        .confirmationDialog(
            "Delete this post?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { post in
            Button("Delete for everyone", role: .destructive) { model.deletePost(post.id) }
        } message: { _ in
            Text("It disappears from your friends' feeds the next time their phones sync.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            PixelAvatarView(avatar: .invader, color: Arcade.green, size: 64)
                .blinking(interval: 0.8)
            Text("NOTHING HERE YET")
                .font(Arcade.font(13))
                .foregroundStyle(Arcade.ink)
            Text(model.friends.isEmpty
                 ? "ADD A PLAYER IN PERSON, THEN YOUR FEED FILLS WITH THEIR POSTS."
                 : "SNAP SOMETHING. ONLY YOUR FRIENDS WILL EVER SEE IT.")
                .font(Arcade.font(9))
                .foregroundStyle(Arcade.cyan)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

struct PostCard: View {
    var post: FeedPost
    var author: PlayerCard?
    var isMine: Bool
    var onPhoto: (AttachmentRef) -> Void
    var onRetry: () -> Void

    var body: some View {
        let color = author?.color.color ?? Arcade.dim
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PixelAvatarView(avatar: author?.avatar ?? .invader, color: color, size: 26)
                Text(author?.name ?? "???")
                    .font(Arcade.font(10))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Spacer()
                Text(Arcade.shortTime(post.createdAt))
                    .font(Arcade.font(8))
                    .foregroundStyle(Arcade.dim)
            }
            if let photo = post.photo {
                Button { onPhoto(photo) } label: {
                    PhotoView(ref: photo)
                }
                .buttonStyle(.plain)
            }
            if !post.text.isEmpty {
                Text(post.text)
                    .font(Arcade.body(15))
                    .foregroundStyle(Arcade.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if isMine {
                DeliveryLabel(status: post.status, onRetry: onRetry)
            }
        }
        .padding(12)
        .pixelPanel(color)
    }
}

/// "SENDING..." / "FAILED - TAP TO RETRY" under your own posts and messages.
struct DeliveryLabel: View {
    var status: DeliveryStatus
    var onRetry: () -> Void

    var body: some View {
        switch status {
        case .sent:
            EmptyView()
        case .sending:
            Text("SENDING...")
                .font(Arcade.font(7))
                .foregroundStyle(Arcade.dim)
                .blinking()
        case .failed:
            Button(action: onRetry) {
                Text("FAILED - TAP TO RETRY")
                    .font(Arcade.font(7))
                    .foregroundStyle(Arcade.red)
            }
        }
    }
}
