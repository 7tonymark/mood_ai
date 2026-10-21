import SwiftUI

/// The fallback for when Bluetooth won't cooperate: both players scan each other's code.
/// Codes expire within a minute, so a screenshot sent from far away is useless.
struct QRExchangeView: View {
    private enum Tab {
        case show, scan
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .show
    @State private var scanned: PlayerCard?
    @State private var scanError: String?
    @State private var cameraError: String?
    @State private var celebration: (card: PlayerCard, result: AppModel.AddResult)?

    var body: some View {
        ArcadeScreen(title: "QR LINK", onClose: { dismiss() }) {
            HStack(spacing: 12) {
                Button("MY CODE") { tab = .show }
                    .buttonStyle(.arcade(Arcade.cyan, filled: tab == .show, size: 10))
                Button("SCAN") { tab = .scan }
                    .buttonStyle(.arcade(Arcade.magenta, filled: tab == .scan, size: 10))
            }
            Text("TAKE TURNS: BOTH PLAYERS\nSCAN EACH OTHER")
                .font(Arcade.font(8))
                .foregroundStyle(Arcade.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            switch tab {
            case .show:
                if let profile = model.profile {
                    MyCodeView(card: profile.card)
                }
            case .scan:
                scanner
            }
            Spacer(minLength: 0)
        }
        .overlay {
            if let scanned {
                confirm(scanned)
            }
            if let celebration {
                NewPlayerBanner(card: celebration.card, result: celebration.result) {
                    self.celebration = nil
                    tab = .show
                }
            }
        }
    }

    private var scanner: some View {
        VStack(spacing: 12) {
            ZStack {
                if let cameraError {
                    Text(cameraError)
                        .font(Arcade.font(12))
                        .foregroundStyle(Arcade.red)
                        .multilineTextAlignment(.center)
                } else {
                    QRScannerView(onCode: handle, onFailure: { cameraError = $0 })
                        .clipShape(PixelRect())
                    ScannerBrackets()
                        .padding(36)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .pixelPanel(Arcade.magenta, fill: .black)

            Text(scanError ?? "POINT AT THEIR CODE")
                .font(Arcade.font(9))
                .foregroundStyle(scanError == nil ? Arcade.cyan : Arcade.orange)
                .multilineTextAlignment(.center)
        }
    }

    private func handle(_ code: String) {
        guard scanned == nil, celebration == nil else { return }
        switch QRPayload.parse(code) {
        case .success(let card):
            scanError = nil
            Haptics.tick()
            scanned = card
        case .failure(.expired):
            scanError = "CODE EXPIRED.\nASK FOR A FRESH ONE."
            Haptics.error()
        case .failure:
            scanError = "NOT A PROXIMITY CODE"
            Haptics.error()
        }
    }

    private func confirm(_ card: PlayerCard) -> some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("ADD PLAYER?")
                    .font(Arcade.font(16))
                    .foregroundStyle(Arcade.yellow)
                    .neon(Arcade.yellow, radius: 4)
                PixelAvatarView(avatar: card.avatar, color: card.color.color, size: 80)
                Text(card.name)
                    .font(Arcade.font(14))
                    .foregroundStyle(card.color.color)
                HStack(spacing: 12) {
                    Button("NO") { scanned = nil }
                        .buttonStyle(.arcade(Arcade.red, filled: false))
                    Button("YES") {
                        let result = model.addFriend(card, via: .qr)
                        if result == .added { Haptics.success() }
                        scanned = nil
                        celebration = (card, result)
                    }
                    .buttonStyle(.arcade(Arcade.green))
                }
            }
            .padding(24)
            .pixelPanel(Arcade.yellow)
            .padding(24)
        }
    }
}

private struct MyCodeView: View {
    var card: PlayerCard

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let payload = QRPayload.current(for: card, now: context.date)
            let remaining = payload.exp.timeIntervalSince(context.date) - QRPayload.grace
            VStack(spacing: 14) {
                QRImage(string: payload.string())
                    .padding(14)
                    .background(Color.white)
                    .clipShape(PixelRect())
                    .padding(8)
                    .pixelPanel(Arcade.cyan)

                // Countdown bar until the code refreshes.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Arcade.dim.opacity(0.3))
                        Rectangle()
                            .fill(remaining > 8 ? Arcade.green : Arcade.orange)
                            .frame(width: geometry.size.width * max(0, remaining) / QRPayload.window)
                    }
                }
                .frame(height: 8)

                Text("NEW CODE IN \(max(0, Int(remaining.rounded(.up))))")
                    .font(Arcade.font(8))
                    .foregroundStyle(Arcade.dim)
            }
        }
    }
}

/// Renders a QR code once per distinct string rather than on every frame.
private struct QRImage: View {
    var string: String
    @State private var image: UIImage?
    @State private var rendered: String?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Your friend code")
        .onAppear(perform: render)
        .onChange(of: string) { render() }
    }

    private func render() {
        guard rendered != string else { return }
        rendered = string
        image = QRCodeImage.make(from: string)
    }
}

/// Pixel corner brackets framing the camera view.
private struct ScannerBrackets: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height, l: CGFloat = 28
            Path { path in
                path.move(to: CGPoint(x: 0, y: l)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: l, y: 0))
                path.move(to: CGPoint(x: w - l, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: l))
                path.move(to: CGPoint(x: w, y: h - l)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - l, y: h))
                path.move(to: CGPoint(x: l, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(Arcade.magenta, style: StrokeStyle(lineWidth: 5, lineCap: .square))
            .neon(Arcade.magenta, radius: 4)
        }
        .allowsHitTesting(false)
    }
}
