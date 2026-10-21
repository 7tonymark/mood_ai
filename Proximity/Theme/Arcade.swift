import SwiftUI
import UIKit

/// The arcade palette and type: neon on near-black, everything set in a pixel font.
enum Arcade {
    static let background = Color(red: 0.03, green: 0.01, blue: 0.09)
    static let panel = Color(red: 0.08, green: 0.04, blue: 0.18)
    static let ink = Color.white
    static let dim = Color(white: 0.55)

    static let cyan = Color(red: 0.00, green: 0.94, blue: 1.00)
    static let magenta = Color(red: 1.00, green: 0.17, blue: 0.84)
    static let yellow = Color(red: 1.00, green: 0.90, blue: 0.00)
    static let green = Color(red: 0.22, green: 1.00, blue: 0.08)
    static let orange = Color(red: 1.00, green: 0.54, blue: 0.00)
    static let red = Color(red: 1.00, green: 0.23, blue: 0.23)

    private static let fontName = "PressStart2P-Regular"
    private static let hasPixelFont = UIFont(name: fontName, size: 12) != nil

    static func font(_ size: CGFloat) -> Font {
        hasPixelFont
            ? .custom(fontName, size: size)
            : .system(size: size * 1.2, weight: .heavy, design: .monospaced)
    }

    /// For what people write. The pixel font has no emoji or accents, so posts and chats use
    /// a monospaced system font that keeps the terminal feel and can draw every language.
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// "NOW", "5M", "3H", "2D", then a date: like a high-score table, not a calendar.
    static func shortTime(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "NOW"
        case ..<3600: return "\(Int(seconds / 60))M"
        case ..<86_400: return "\(Int(seconds / 3600))H"
        case ..<604_800: return "\(Int(seconds / 86_400))D"
        default: return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
    }
}

extension PlayerColor {
    var color: Color {
        switch self {
        case .cyan: Arcade.cyan
        case .magenta: Arcade.magenta
        case .yellow: Arcade.yellow
        case .green: Arcade.green
        case .orange: Arcade.orange
        case .red: Arcade.red
        }
    }
}

extension View {
    /// A CRT-style glow.
    func neon(_ color: Color, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.8), radius: radius)
            .shadow(color: color.opacity(0.35), radius: radius * 2)
    }

    /// A chunky framed panel with stepped "pixel" corners and a hard drop shadow.
    func pixelPanel(_ color: Color = Arcade.cyan, fill: Color = Arcade.panel) -> some View {
        background(PixelRect().fill(fill))
            .overlay(PixelRect().strokeBorder(color, lineWidth: 3))
            .background(PixelRect().fill(color.opacity(0.3)).offset(x: 5, y: 5))
    }

    func blinking(_ active: Bool = true, interval: TimeInterval = 0.55) -> some View {
        modifier(Blink(active: active, interval: interval))
    }
}

/// A rectangle whose corners are cut in one pixel step, like an 8-bit window frame.
struct PixelRect: InsettableShape {
    var step: CGFloat = 5
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let s = min(step, r.width / 4, r.height / 4)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + s, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - s, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + s))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - s))
        path.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        path.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + s, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - s))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + s))
        path.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PixelRect {
        var shape = self
        shape.inset += amount
        return shape
    }
}

private struct Blink: ViewModifier {
    var active: Bool
    var interval: TimeInterval

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / interval)
            content.opacity(!active || tick.isMultiple(of: 2) ? 1 : 0.15)
        }
    }
}
