import SwiftUI

/// Shown on a new phone when iCloud has a player but iCloud Keychain hasn't delivered their keys.
struct RestoreView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingFreshStart = false
    @State private var retrying = false

    var body: some View {
        ArcadeScreen(title: "CONTINUE?") {
            Spacer()
            if let found = model.pendingRestore {
                PixelAvatarView(avatar: found.profile.avatar, color: found.profile.color.color, size: 96)
                Text(found.profile.name)
                    .font(Arcade.font(18))
                    .foregroundStyle(found.profile.color.color)
            }
            Text("YOUR PLAYER IS IN ICLOUD, BUT ITS KEYS HAVEN'T REACHED THIS PHONE.")
                .font(Arcade.font(10))
                .foregroundStyle(Arcade.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Text("Keys sync through iCloud Keychain. Check Settings > your name > iCloud > Passwords & Keychain is on, wait a minute, then try again.")
                .font(Arcade.body(13))
                .foregroundStyle(Arcade.dim)
                .multilineTextAlignment(.center)
            Spacer()
            Button(retrying ? "CHECKING..." : "TRY AGAIN") {
                retrying = true
                Task {
                    await model.retryRestore()
                    retrying = false
                }
            }
            .buttonStyle(.arcade(Arcade.green, size: 14))
            .disabled(retrying)
            Button("START AS A NEW PLAYER") { confirmingFreshStart = true }
                .buttonStyle(.arcade(Arcade.red, filled: false, size: 10))
                .padding(.bottom, 6)
        }
        .confirmationDialog("Start over?", isPresented: $confirmingFreshStart, titleVisibility: .visible) {
            Button("Start as a new player", role: .destructive) {
                Task { await model.startAsNewPlayer() }
            }
        } message: {
            Text("Your old friends pinned your old keys, so each of them will need to add you again in person.")
        }
    }
}
