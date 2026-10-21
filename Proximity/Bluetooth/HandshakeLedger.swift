import Foundation

/// The rules of a Bluetooth friend request, kept free of CoreBluetooth so they can be unit tested.
///
/// A friendship only completes when *both* players accepted each other: I wrote my card to
/// their phone (`iAccepted`) and they wrote their card to mine (`theyAccepted`).
struct HandshakeLedger {
    struct Entry: Equatable {
        var card: PlayerCard
        var iAccepted = false
        var theyAccepted = false
        var completed = false
    }

    private(set) var entries: [UUID: Entry] = [:]

    mutating func discovered(_ card: PlayerCard) {
        if entries[card.id] == nil {
            entries[card.id] = Entry(card: card)
        } else {
            entries[card.id]?.card = card
        }
    }

    /// Returns the card when this acceptance completes the friendship.
    @discardableResult
    mutating func markIAccepted(_ id: UUID) -> PlayerCard? {
        guard entries[id] != nil else { return nil }
        entries[id]?.iAccepted = true
        return completeIfReady(id)
    }

    /// Returns the card when this acceptance completes the friendship.
    @discardableResult
    mutating func markTheyAccepted(_ card: PlayerCard) -> PlayerCard? {
        discovered(card)
        entries[card.id]?.theyAccepted = true
        return completeIfReady(card.id)
    }

    private mutating func completeIfReady(_ id: UUID) -> PlayerCard? {
        guard let entry = entries[id], entry.iAccepted, entry.theyAccepted, !entry.completed else { return nil }
        entries[id]?.completed = true
        return entry.card
    }
}
