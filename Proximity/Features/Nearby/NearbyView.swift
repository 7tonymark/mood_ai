import SwiftUI
import UIKit

/// "ADD PLAYER": find people standing next to you over Bluetooth and add each other.
struct NearbyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var handshake: NearbyHandshake?
    @State private var celebration: (card: PlayerCard, result: AppModel.AddResult)?

    var body: some View {
        ArcadeScreen(title: "ADD PLAYER", onClose: { dismiss() }) {
            if let handshake {
                content(for: handshake)
            }
        }
        .overlay {
            if let celebration {
                NewPlayerBanner(card: celebration.card, result: celebration.result) {
                    self.celebration = nil
                }
            }
        }
        .onAppear(perform: start)
        .onDisappear { handshake?.stop() }
    }

    private func start() {
        guard handshake == nil, let profile = model.profile else { return }
        let session = NearbyHandshake(myCard: profile.card)
        session.onFriendAdded = { card in
            let result = model.addFriend(card, via: .bluetooth)
            celebration = (card, result)
        }
        session.start()
        handshake = session
    }

    @ViewBuilder
    private func content(for handshake: NearbyHandshake) -> some View {
        switch handshake.status {
        case .starting:
            message("WARMING UP RADIO...", color: Arcade.cyan, blink: true)
        case .poweredOff:
            message("TURN ON BLUETOOTH\nTO FIND PLAYERS", color: Arcade.orange)
        case .unsupported:
            message("THIS DEVICE CAN'T\nDO BLUETOOTH LE", color: Arcade.red)
        case .unauthorized:
            message("BLUETOOTH ACCESS\nDENIED", color: Arcade.red)
            Button("OPEN SETTINGS") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.arcade(Arcade.cyan))
        case .searching:
            searching(handshake)
        }
    }

    private func searching(_ handshake: NearbyHandshake) -> some View {
        VStack(spacing: 14) {
            if let profile = model.profile {
                RadarView(avatar: profile.avatar, color: profile.color.color)
            }
            Text(handshake.peers.isEmpty ? "SEARCHING FOR PLAYERS..." : "PLAYERS NEARBY")
                .font(Arcade.font(10))
                .foregroundStyle(Arcade.cyan)
                .blinking(handshake.peers.isEmpty)
            Text("BOTH OPEN THIS SCREEN AND\nHOLD YOUR PHONES TOGETHER")
                .font(Arcade.font(8))
                .foregroundStyle(Arcade.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(handshake.peers) { peer in
                        PeerRow(peer: peer, alreadyFriends: model.isFriend(peer.id)) {
                            handshake.accept(peer.id)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 5)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func message(_ text: String, color: Color, blink: Bool = false) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(Arcade.font(14))
                .foregroundStyle(color)
                .neon(color, radius: 4)
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .blinking(blink)
            Spacer()
        }
    }
}

private struct PeerRow: View {
    var peer: NearbyHandshake.Peer
    var alreadyFriends: Bool
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PixelAvatarView(avatar: peer.card.avatar, color: peer.card.color.color, size: 40)
                VStack(alignment: .leading, spacing: 8) {
                    Text(peer.card.name)
                        .font(Arcade.font(12))
                        .foregroundStyle(peer.card.color.color)
                        .lineLimit(1)
                    if let caption {
                        Text(caption)
                            .font(Arcade.font(7))
                            .foregroundStyle(Arcade.yellow)
                    }
                }
                Spacer()
                SignalBars(rssi: peer.rssi)
            }
            Button(action: onAccept) {
                Text(buttonTitle)
            }
            .buttonStyle(.arcade(buttonColor, size: 10))
            // A finished handshake stays green rather than greyed out, but can't be pressed again.
            .disabled(!canPress && !peer.completed)
            .allowsHitTesting(canPress)
        }
        .padding(12)
        .pixelPanel(peer.card.color.color)
    }

    private var canPress: Bool {
        !peer.completed && !peer.iAccepted && !peer.sending && peer.canSend && peer.isClose
    }

    private var caption: String? {
        if peer.theyAccepted && !peer.completed { return "WANTS TO ADD YOU" }
        if alreadyFriends && !peer.completed { return "ALREADY ON YOUR LIST" }
        return nil
    }

    private var buttonTitle: String {
        if peer.completed { return "ADDED!" }
        if peer.iAccepted { return "WAITING FOR THEM..." }
        if peer.sending { return "SENDING..." }
        if !peer.canSend { return "LINKING..." }
        if !peer.isClose { return "GET CLOSER" }
        return peer.theyAccepted ? "ACCEPT" : "ADD"
    }

    private var buttonColor: Color {
        if peer.completed || peer.theyAccepted { return Arcade.green }
        return Arcade.magenta
    }
}
