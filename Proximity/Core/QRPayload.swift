import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// The QR fallback: my signed card and inbox with a short expiry, signed again as a whole so the
/// expiry can't be stretched. A screenshot sent over chat stops working within a minute.
enum QRPayload {
    static let prefix = "PRXY2:"
    static let version: UInt8 = 1
    /// Each code is shown for this long before a new one replaces it.
    static let window: TimeInterval = 30
    /// Extra time a scanner allows for a code that was on screen at the end of its window.
    static let grace: TimeInterval = 15

    enum ParseError: Error, Equatable {
        case notOurs, malformed, expired
    }

    static func windowStart(for now: Date) -> TimeInterval {
        (now.timeIntervalSince1970 / window).rounded(.down) * window
    }

    static func make(identity: Identity, card: PlayerCard, now: Date = Date()) throws -> String {
        var writer = ByteWriter()
        writer.u8(version)
        writer.raw(card.encoded)
        writer.u64(UInt64(windowStart(for: now) + window + grace))
        writer.raw(identity.inbox)
        writer.raw(try identity.sign(Domain.qr + writer.data))
        return prefix + Base64URL.encode(writer.data)
    }

    static func parse(_ string: String, now: Date = Date()) -> Result<Introduction, ParseError> {
        guard string.hasPrefix(prefix) else { return .failure(.notOurs) }
        guard let data = Base64URL.decode(String(string.dropFirst(prefix.count))) else { return .failure(.malformed) }

        var reader = ByteReader(data)
        guard let version = try? reader.u8(), version == Self.version,
              let card = try? PlayerCard.read(from: &reader),
              let expiry = try? reader.u64(),
              let inbox = try? reader.raw(16) else { return .failure(.malformed) }
        let signed = reader.consumed
        guard let signature = try? reader.raw(64), reader.isAtEnd,
              let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: card.signingKey),
              signer.isValidSignature(signature, for: Domain.qr + signed) else { return .failure(.malformed) }

        // Reject expired codes, and codes claiming to live suspiciously long.
        let remaining = TimeInterval(expiry) - now.timeIntervalSince1970
        guard remaining >= 0, remaining <= window + grace else { return .failure(.expired) }
        return .success(Introduction(card: card, inbox: inbox))
    }
}
