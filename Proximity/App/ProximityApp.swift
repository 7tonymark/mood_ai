import SwiftUI

@main
@MainActor
struct ProximityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel(
        store: LocalStore(),
        backend: Platform.makeBackend(),
        identityStore: KeychainIdentityStore()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                // The pixel font is wide; past this size the arcade layouts stop fitting.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                BootView()
            case .restore:
                RestoreView()
            case .setup:
                ProfileSetupView(mode: .create)
            case .ready:
                MainView()
            }
        }
        .task { await model.boot() }
    }
}

struct BootView: View {
    var body: some View {
        ArcadeScreen {
            Spacer()
            ArcadeLogo()
            Text("LOADING...")
                .font(Arcade.font(12))
                .foregroundStyle(Arcade.ink)
                .blinking()
            Spacer()
        }
    }
}
