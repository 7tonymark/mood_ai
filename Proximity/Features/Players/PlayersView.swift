import SwiftUI

/// The friend list, styled as a high-score table.
struct PlayersView: View {
    var onChat: (UUID) -> Void

    @Environment(AppModel.self) private var model
    @State private var showNearby = false
    @State private var showQR = false
    @State private var pendingRemoval: Friend?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("FRIENDS ARE ADDED IN PERSON ONLY")
                    .font(Arcade.font(7))
                    .foregroundStyle(Arcade.dim)
                Spacer()
                Text(String(format: "%03d/%d", model.friends.count, AppModel.maxFriends))
                    .font(Arcade.font(9))
                    .foregroundStyle(Arcade.green)
                    .accessibilityLabel("\(model.friends.count) of \(AppModel.maxFriends) friends")
            }

            if model.friends.isEmpty {
                emptyState
            } else {
                roster
            }

            HStack(spacing: 12) {
                Button("+ ADD PLAYER") { showNearby = true }
                    .buttonStyle(.arcade(Arcade.magenta, size: 11))
                Button("QR") { showQR = true }
                    .buttonStyle(.arcade(Arcade.cyan, filled: false, size: 11))
                    .frame(width: 88)
            }
            .disabled(model.friends.count >= AppModel.maxFriends)
        }
        .fullScreenCover(isPresented: $showNearby) { NearbyView() }
        .fullScreenCover(isPresented: $showQR) { QRExchangeView() }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { friend in
            Button("Remove", role: .destructive) { model.removeFriend(friend.id) }
        } message: { _ in
            Text("Their posts and your chat disappear from your phone, and you disappear from theirs. You'll have to meet in person to re-add each other.")
        }
    }

    private var roster: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                HStack {
                    Text("RANK").frame(width: 52, alignment: .leading)
                    Text("NAME")
                    Spacer()
                    Text("MET")
                }
                .font(Arcade.font(8))
                .foregroundStyle(Arcade.dim)
                .padding(.horizontal, 12)

                ForEach(Array(model.friends.enumerated()), id: \.element.id) { index, friend in
                    Button { onChat(friend.id) } label: {
                        FriendRow(rank: index + 1, friend: friend)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Chat", systemImage: "bubble.left") { onChat(friend.id) }
                        Button("Remove", systemImage: "trash", role: .destructive) { pendingRemoval = friend }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 5) // room for the panel shadows
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            PixelAvatarView(avatar: .invader, color: Arcade.green, size: 72)
                .blinking(interval: 0.8)
            Text("NO PLAYERS YET")
                .font(Arcade.font(14))
                .foregroundStyle(Arcade.ink)
            Text("FIND SOMEONE, HOLD YOUR PHONES TOGETHER AND PRESS ADD PLAYER.")
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

private struct FriendRow: View {
    var rank: Int
    var friend: Friend

    private static let metFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd.yy"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.ordinal(rank))
                .font(Arcade.font(10))
                .foregroundStyle(rank <= 3 ? Arcade.yellow : Arcade.dim)
                .frame(width: 40, alignment: .leading)
            PixelAvatarView(avatar: friend.avatar, color: friend.color.color, size: 32)
            Text(friend.name)
                .font(Arcade.font(11))
                .foregroundStyle(friend.color.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Self.metFormat.string(from: friend.addedAt))
                Text(friend.method == .bluetooth ? "BT" : "QR")
                    .foregroundStyle(Arcade.dim)
            }
            .font(Arcade.font(8))
            .foregroundStyle(Arcade.ink)
        }
        .padding(12)
        .pixelPanel(friend.color.color.opacity(0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(friend.name), met \(friend.addedAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Opens your chat")
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "TH"
        case (1, _): suffix = "ST"
        case (2, _): suffix = "ND"
        case (3, _): suffix = "RD"
        default: suffix = "TH"
        }
        return "\(n)\(suffix)"
    }
}
