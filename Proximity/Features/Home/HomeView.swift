import SwiftUI

/// The friend list, styled as a high-score table.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showNearby = false
    @State private var showQR = false
    @State private var editingProfile = false
    @State private var pendingRemoval: Friend?

    var body: some View {
        ArcadeScreen {
            header
            if model.friends.isEmpty {
                emptyState
            } else {
                roster
            }
            HStack(spacing: 12) {
                Button("+ ADD PLAYER") { showNearby = true }
                    .buttonStyle(.arcade(Arcade.magenta))
                Button("QR") { showQR = true }
                    .buttonStyle(.arcade(Arcade.cyan, filled: false))
                    .frame(width: 96)
            }
            .disabled(model.friends.count >= AppModel.maxFriends)
            .padding(.bottom, 6)
        }
        .fullScreenCover(isPresented: $showNearby) { NearbyView() }
        .fullScreenCover(isPresented: $showQR) { QRExchangeView() }
        .fullScreenCover(isPresented: $editingProfile) { ProfileSetupView(mode: .edit) }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { friend in
            Button("Remove", role: .destructive) { model.removeFriend(friend.id) }
        } message: { _ in
            Text("You'll have to meet in person again to re-add them.")
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Button { editingProfile = true } label: {
                    HStack(spacing: 10) {
                        if let profile = model.profile {
                            PixelAvatarView(avatar: profile.avatar, color: profile.color.color, size: 28)
                            Text(profile.name)
                                .font(Arcade.font(10))
                                .foregroundStyle(profile.color.color)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .pixelPanel(model.profile?.color.color ?? Arcade.cyan)
                }
                .accessibilityLabel("Edit your player")
                Spacer()
                Text(String(format: "%03d/%d", model.friends.count, AppModel.maxFriends))
                    .font(Arcade.font(10))
                    .foregroundStyle(Arcade.green)
                    .accessibilityLabel("\(model.friends.count) of \(AppModel.maxFriends) friends")
            }
            .padding(.top, 8)

            Text("PLAYERS")
                .font(Arcade.font(24))
                .foregroundStyle(Arcade.yellow)
                .neon(Arcade.yellow)

            if let warning = model.cloudWarning {
                Text(warning)
                    .font(Arcade.font(8))
                    .foregroundStyle(Arcade.orange)
                    .multilineTextAlignment(.center)
            }
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
                    FriendRow(rank: index + 1, friend: friend)
                        .contextMenu {
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
            Text("FRIENDS CAN ONLY BE ADDED IN PERSON.\n\nFIND SOMEONE, HOLD YOUR PHONES TOGETHER AND PRESS ADD PLAYER.")
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
