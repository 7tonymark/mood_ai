import SwiftUI

enum PlayerColor: Int, Codable, CaseIterable, Identifiable {
    case cyan, magenta, yellow, green, orange, red

    var id: Int { rawValue }

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

/// The public "business card" two phones swap when they meet.
/// It deliberately holds nothing but what a friend sees: no Apple ID, phone number or email.
struct PlayerCard: Codable, Hashable {
    static let currentVersion = 1

    var v: Int = PlayerCard.currentVersion
    var id: UUID
    var name: String
    var color: PlayerColor
    var avatar: PixelAvatar

    // Short keys keep the card well under a single Bluetooth write.
    enum CodingKeys: String, CodingKey {
        case v, id, name = "n", color = "c", avatar = "a"
    }

    func encoded() -> Data {
        // Encoding a struct of plain values cannot fail.
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    static func decode(_ data: Data) -> PlayerCard? {
        guard let card = try? JSONDecoder().decode(PlayerCard.self, from: data),
              card.v == currentVersion,
              Profile.isValidName(card.name) else { return nil }
        return card
    }
}

struct Profile: Codable, Equatable {
    static let maxNameLength = 12

    var id: UUID
    var name: String
    var color: PlayerColor
    var avatar: PixelAvatar

    var card: PlayerCard {
        PlayerCard(id: id, name: name, color: color, avatar: avatar)
    }

    /// The pixel font only has ASCII glyphs, so names are limited to what it can draw.
    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.!")

    /// Uppercases and strips what the user typed, as they type it.
    static func sanitize(_ input: String) -> String {
        let cleaned = input.uppercased().filter { allowed.contains($0) }
        return String(cleaned.prefix(maxNameLength))
    }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && sanitize(name) == name
    }
}

struct Friend: Codable, Identifiable, Hashable {
    enum Method: String, Codable {
        case bluetooth, qr
    }

    var id: UUID
    var name: String
    var color: PlayerColor
    var avatar: PixelAvatar
    var addedAt: Date
    var method: Method

    init(card: PlayerCard, method: Method, addedAt: Date = .now) {
        self.id = card.id
        self.name = card.name
        self.color = card.color
        self.avatar = card.avatar
        self.addedAt = addedAt
        self.method = method
    }

    /// Meeting someone again picks up their latest name and look.
    mutating func refresh(from card: PlayerCard) {
        name = card.name
        color = card.color
        avatar = card.avatar
    }
}
