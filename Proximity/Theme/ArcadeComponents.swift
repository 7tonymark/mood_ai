import SwiftUI

/// A chunky arcade cabinet button that physically "presses down" onto its shadow.
struct ArcadeButtonStyle: ButtonStyle {
    var color: Color = Arcade.magenta
    var filled = true
    var size: CGFloat = 12

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let tint = isEnabled ? color : Arcade.dim
        return configuration.label
            .font(Arcade.font(size))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(filled ? Arcade.background : tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(PixelRect().fill(filled ? tint : Arcade.panel))
            .overlay(PixelRect().strokeBorder(tint, lineWidth: 3))
            .background(PixelRect().fill(tint.opacity(0.45)).offset(y: pressed ? 0 : 5))
            .offset(y: pressed ? 5 : 0)
            .neon(tint.opacity(isEnabled ? 0.9 : 0), radius: 4)
            .animation(.linear(duration: 0.04), value: pressed)
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: pressed) { _, isPressed in isPressed }
    }
}

extension ButtonStyle where Self == ArcadeButtonStyle {
    static func arcade(_ color: Color = Arcade.magenta, filled: Bool = true, size: CGFloat = 12) -> ArcadeButtonStyle {
        ArcadeButtonStyle(color: color, filled: filled, size: size)
    }
}

/// A full screen with the arcade backdrop, an optional close button and a neon title.
struct ArcadeScreen<Content: View>: View {
    var title: String?
    var onClose: (() -> Void)?
    var content: Content

    init(title: String? = nil, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            if title != nil || onClose != nil {
                ZStack {
                    if let title {
                        Text(title)
                            .font(Arcade.font(18))
                            .foregroundStyle(Arcade.yellow)
                            .neon(Arcade.yellow, radius: 4)
                    }
                    if let onClose {
                        HStack {
                            Button(action: onClose) {
                                Text("X")
                                    .font(Arcade.font(16))
                                    .foregroundStyle(Arcade.red)
                                    .padding(10)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Close")
                            Spacer()
                        }
                    }
                }
                .padding(.top, 8)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArcadeBackground())
        .overlay(Scanlines())
    }
}

struct ArcadeLogo: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("PROXIMITY")
                .font(Arcade.font(26))
                .foregroundStyle(Arcade.magenta)
                .neon(Arcade.magenta)
            Text("FRIENDS IRL ONLY")
                .font(Arcade.font(10))
                .foregroundStyle(Arcade.cyan)
        }
        .padding(.vertical, 12)
    }
}

/// Starfield over a scrolling synthwave grid, behind every screen.
struct ArcadeBackground: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Arcade.background
            Starfield()
            GridFloor()
                .frame(height: 220)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct Starfield: View {
    private struct Star {
        let x: CGFloat, y: CGFloat, speed: CGFloat, size: CGFloat, tint: Int
    }

    private static let stars: [Star] = {
        // A fixed seed keeps the sky identical on every screen.
        var seed: UInt64 = 0x5EED_CAFE
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        return (0..<90).map { _ in
            Star(x: next(), y: next(), speed: 6 + next() * 30, size: next() < 0.8 ? 2 : 3, tint: Int(next() * 3))
        }
    }()

    private static let tints = [Color.white, Arcade.cyan, Arcade.magenta]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let t = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
                for star in Self.stars {
                    let y = (star.y * size.height + t * star.speed).truncatingRemainder(dividingBy: size.height)
                    let rect = CGRect(x: (star.x * size.width).rounded(), y: y.rounded(), width: star.size, height: star.size)
                    context.fill(Path(rect), with: .color(Self.tints[star.tint].opacity(0.7)))
                }
            }
        }
    }
}

struct GridFloor: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1))
                var path = Path()
                // Horizontal lines bunch up toward the horizon and roll toward the viewer.
                let rows = 10
                for i in 0..<rows {
                    let f = (CGFloat(i) + phase) / CGFloat(rows)
                    let y = size.height * f * f
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                // Vertical lines fan out from a vanishing point.
                let mid = size.width / 2
                for k in -8...8 {
                    path.move(to: CGPoint(x: mid + CGFloat(k) * 10, y: 0))
                    path.addLine(to: CGPoint(x: mid + CGFloat(k) * size.width / 6, y: size.height))
                }
                context.stroke(path, with: .color(Arcade.magenta.opacity(0.55)), lineWidth: 1.5)
            }
        }
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
    }
}

/// Faint horizontal CRT scanlines over the whole screen.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            context.fill(path, with: .color(.black.opacity(0.22)))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PixelAvatarView: View {
    var avatar: PixelAvatar
    var color: Color
    var size: CGFloat = 40

    var body: some View {
        Canvas { context, canvasSize in
            let cell = canvasSize.width / CGFloat(PixelAvatar.size)
            for y in 0..<PixelAvatar.size {
                for x in 0..<PixelAvatar.size where avatar[x, y] {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .neon(color, radius: max(2, size / 20))
        .accessibilityHidden(true)
    }
}

/// Five-bar signal meter: how close the other phone is.
struct SignalBars: View {
    var rssi: Int?

    var body: some View {
        let lit = BLE.bars(for: rssi)
        let color = lit >= 4 ? Arcade.green : lit >= 2 ? Arcade.yellow : Arcade.red
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? color : Arcade.dim.opacity(0.3))
                    .frame(width: 5, height: CGFloat(5 + i * 4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Signal \(lit) of 5")
    }
}

/// Pulsing rings around my avatar while searching.
struct RadarView: View {
    var avatar: PixelAvatar
    var color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let progress = CGFloat((t / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1))
                    Circle()
                        .stroke(Arcade.cyan.opacity(1 - progress), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                        .frame(width: 60 + progress * 160, height: 60 + progress * 160)
                }
                PixelAvatarView(avatar: avatar, color: color, size: 48)
            }
            .frame(width: 220, height: 220)
        }
        .accessibilityHidden(true)
    }
}

/// Full-screen "NEW PLAYER!" moment after a successful add.
struct NewPlayerBanner: View {
    var card: PlayerCard
    var result: AppModel.AddResult
    var onDismiss: () -> Void

    private static let flash = [Arcade.yellow, Arcade.magenta, Arcade.cyan, Arcade.green]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 0.15)) { context in
                    let i = Int(context.date.timeIntervalSinceReferenceDate / 0.15) % Self.flash.count
                    Text(headline)
                        .font(Arcade.font(22))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Self.flash[i])
                        .neon(Self.flash[i])
                }
                PixelAvatarView(avatar: card.avatar, color: card.color.color, size: 120)
                Text(card.name)
                    .font(Arcade.font(18))
                    .foregroundStyle(card.color.color)
                Text(detail)
                    .font(Arcade.font(10))
                    .foregroundStyle(Arcade.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                Button("CONTINUE", action: onDismiss)
                    .buttonStyle(.arcade(Arcade.cyan))
                    .padding(.horizontal, 40)
            }
            .padding(24)
        }
        .overlay(Scanlines())
    }

    private var headline: String {
        switch result {
        case .added: "NEW PLAYER!"
        case .alreadyFriends: "PLAYER\nUPDATED"
        case .listFull: "ROSTER FULL"
        case .isMe: "THAT'S YOU!"
        }
    }

    private var detail: String {
        switch result {
        case .added: "+1 FRIEND"
        case .alreadyFriends: "ALREADY FRIENDS.\nNAME AND AVATAR REFRESHED."
        case .listFull: "YOU HAVE \(AppModel.maxFriends) FRIENDS.\nREMOVE ONE TO ADD MORE."
        case .isMe: "SCAN SOMEONE ELSE'S CODE."
        }
    }
}
