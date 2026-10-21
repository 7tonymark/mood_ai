import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// What the QR fallback encodes: my card plus a short expiry, so a screenshot sent
/// over chat stops working within a minute. The code on screen refreshes every window.
struct QRPayload: Codable, Equatable {
    static let prefix = "PRXY1:"
    /// Each code is shown for this long before a new one replaces it.
    static let window: TimeInterval = 30
    /// Extra time a scanner allows for a code that was on screen at the end of its window.
    static let grace: TimeInterval = 15

    enum ParseError: Error, Equatable {
        case notOurs, malformed, expired
    }

    var card: PlayerCard
    var exp: Date

    /// The payload for the window containing `now`.
    static func current(for card: PlayerCard, now: Date = .now) -> QRPayload {
        let windowStart = (now.timeIntervalSince1970 / window).rounded(.down) * window
        return QRPayload(card: card, exp: Date(timeIntervalSince1970: windowStart + window + grace))
    }

    func string() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(self)) ?? Data()
        let base64url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.prefix + base64url
    }

    static func parse(_ string: String, now: Date = .now) -> Result<PlayerCard, ParseError> {
        guard string.hasPrefix(prefix) else { return .failure(.notOurs) }
        var base64 = String(string.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = Data(base64Encoded: base64),
              let payload = try? decoder.decode(QRPayload.self, from: data),
              payload.card.v == PlayerCard.currentVersion,
              Profile.isValidName(payload.card.name) else { return .failure(.malformed) }

        // Reject codes that have expired, and codes claiming to live suspiciously long.
        let remaining = payload.exp.timeIntervalSince(now)
        guard remaining >= 0, remaining <= window + grace else { return .failure(.expired) }
        return .success(payload.card)
    }
}

enum QRCodeImage {
    private static let context = CIContext()

    static func make(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
