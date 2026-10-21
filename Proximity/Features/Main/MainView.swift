import SwiftUI

enum MainTab: CaseIterable {
    case feed, chat, players

    var title: String {
        switch self {
        case .feed: "FEED"
        case .chat: "CHAT"
        case .players: "PLAYERS"
        }
    }

    var color: Color {
        switch self {
        case .feed: Arcade.green
        case .chat: Arcade.magenta
        case .players: Arcade.cyan
        }
    }
}

/// Wraps a friend id so it can drive `fullScreenCover(item:)`.
struct ConversationTarget: Identifiable {
    let id: UUID
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: MainTab = .feed
    @State private var conversation: ConversationTarget?
    @State private var editingProfile = false

    var body: some View {
        ArcadeScreen {
            header
            switch tab {
            case .feed:
                FeedView()
            case .chat:
                ChatListView { conversation = ConversationTarget(id: $0) }
            case .players:
                PlayersView { conversation = ConversationTarget(id: $0) }
            }
            ArcadeTabBar(selection: $tab, unreadChats: model.totalUnread)
                .padding(.bottom, 4)
        }
        .fullScreenCover(item: $conversation) { target in
            ConversationView(friendID: target.id)
        }
        .fullScreenCover(isPresented: $editingProfile) {
            ProfileSetupView(mode: .edit)
        }
        .task {
            await Platform.requestNotifications()
        }
        .task {
            // Push notifications wake the phone when it's closed; while it's open, poll.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await model.sync()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await model.sync() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                Button { editingProfile = true } label: {
                    HStack(spacing: 10) {
                        if let card = model.myCard {
                            PixelAvatarView(avatar: card.avatar, color: card.color.color, size: 24)
                            Text(card.name)
                                .font(Arcade.font(9))
                                .foregroundStyle(card.color.color)
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .pixelPanel(model.myCard?.color.color ?? Arcade.cyan)
                }
                .accessibilityLabel("Edit your player")
                Spacer()
                Text(tab.title)
                    .font(Arcade.font(20))
                    .foregroundStyle(Arcade.yellow)
                    .neon(Arcade.yellow, radius: 4)
            }
            .padding(.top, 8)

            if let warning = model.cloudWarning {
                Text(warning)
                    .font(Arcade.font(7))
                    .foregroundStyle(Arcade.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ArcadeTabBar: View {
    @Binding var selection: MainTab
    var unreadChats: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    Text(tab.title)
                }
                .buttonStyle(.arcade(tab.color, filled: selection == tab, size: 9))
                .overlay(alignment: .topTrailing) {
                    if tab == .chat, unreadChats > 0 {
                        Text(unreadChats > 99 ? "99+" : "\(unreadChats)")
                            .font(Arcade.font(7))
                            .foregroundStyle(Arcade.background)
                            .padding(4)
                            .background(Arcade.yellow)
                            .offset(x: 4, y: -8)
                            .accessibilityLabel("\(unreadChats) unread")
                    }
                }
            }
        }
    }
}
