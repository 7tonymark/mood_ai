import SwiftUI

struct ChatListView: View {
    var onOpen: (UUID) -> Void

    @Environment(AppModel.self) private var model

    /// Most recent conversation first; friends you haven't talked to yet go by when you met.
    private var friends: [Friend] {
        model.friends.sorted { lastActivity($0) > lastActivity($1) }
    }

    private func lastActivity(_ friend: Friend) -> Date {
        model.lastMessage(with: friend.id)?.sentAt ?? friend.addedAt
    }

    var body: some View {
        if model.friends.isEmpty {
            VStack(spacing: 20) {
                Spacer()
                Text("NO ONE TO TALK TO YET")
                    .font(Arcade.font(12))
                    .foregroundStyle(Arcade.ink)
                Text("CHATS OPEN UP WITH EVERY PLAYER YOU ADD IN PERSON.")
                    .font(Arcade.font(9))
                    .foregroundStyle(Arcade.cyan)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(friends) { friend in
                        Button { onOpen(friend.id) } label: {
                            ConversationRow(
                                friend: friend,
                                last: model.lastMessage(with: friend.id),
                                unread: model.unreadCount(with: friend.id),
                                myID: model.myID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 5)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.sync() }
        }
    }
}

private struct ConversationRow: View {
    var friend: Friend
    var last: ChatMessage?
    var unread: Int
    var myID: UUID?

    private var preview: String {
        guard let last else { return "SAY HI!" }
        let prefix = last.from == myID ? "YOU: " : ""
        if last.text.isEmpty { return prefix + "[PHOTO]" }
        return prefix + last.text
    }

    var body: some View {
        HStack(spacing: 12) {
            PixelAvatarView(avatar: friend.avatar, color: friend.color.color, size: 34)
            VStack(alignment: .leading, spacing: 8) {
                Text(friend.name)
                    .font(Arcade.font(11))
                    .foregroundStyle(friend.color.color)
                    .lineLimit(1)
                Text(preview)
                    .font(Arcade.body(13))
                    .foregroundStyle(unread > 0 ? Arcade.ink : Arcade.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                if let last {
                    Text(Arcade.shortTime(last.sentAt))
                        .font(Arcade.font(7))
                        .foregroundStyle(Arcade.dim)
                }
                if unread > 0 {
                    Text("NEW")
                        .font(Arcade.font(7))
                        .foregroundStyle(Arcade.background)
                        .padding(4)
                        .background(Arcade.yellow)
                        .blinking(interval: 0.8)
                }
            }
        }
        .padding(12)
        .pixelPanel(friend.color.color.opacity(unread > 0 ? 1 : 0.6))
        .accessibilityElement(children: .combine)
    }
}
