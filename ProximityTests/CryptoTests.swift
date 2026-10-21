import XCTest
#if canImport(ProximityCore)
@testable import ProximityCore
#else
@testable import Proximity
#endif

final class WireTests: XCTestCase {
    func testRoundTrip() throws {
        var writer = ByteWriter()
        writer.u8(7)
        writer.u64(0x0102_0304_0506_0708)
        writer.short(Data("HI".utf8))
        writer.raw(Data([9, 9]))

        var reader = ByteReader(writer.data)
        XCTAssertEqual(try reader.u8(), 7)
        XCTAssertEqual(try reader.u64(), 0x0102_0304_0506_0708)
        XCTAssertEqual(try reader.short(), Data("HI".utf8))
        XCTAssertEqual(reader.consumed.count, 1 + 8 + 3)
        XCTAssertEqual(reader.rest(), Data([9, 9]))
        XCTAssertTrue(reader.isAtEnd)
        XCTAssertThrowsError(try reader.u8())
    }

    func testReaderHandlesSlices() throws {
        let data = Data([0, 1, 2, 3, 4])
        var reader = ByteReader(data.dropFirst(2))
        XCTAssertEqual(try reader.u8(), 2)
    }

    func testBase64URL() {
        let data = Data((0...255).map { UInt8($0) })
        let encoded = Base64URL.encode(data)
        XCTAssertFalse(encoded.contains("+") || encoded.contains("/") || encoded.contains("="))
        XCTAssertEqual(Base64URL.decode(encoded), data)
    }
}

final class CryptoTests: XCTestCase {
    func testIdentityExportRoundTrip() throws {
        let identity = Identity.generate()
        let restored = try Identity(exported: identity.exported())
        XCTAssertEqual(restored.id, identity.id)
        XCTAssertEqual(restored.agreementPublicKey, identity.agreementPublicKey)
        XCTAssertEqual(restored.inbox, identity.inbox)
        XCTAssertEqual(restored.archive, identity.archive)
        XCTAssertNotEqual(identity.inbox, identity.archive)
    }

    func testPlayerIDsComeFromKeys() {
        let a = Identity.generate()
        let b = Identity.generate()
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.id, PlayerID.derive(from: a.signingPublicKey))
    }

    func testAnonymousBoxRoundTrip() throws {
        let bob = Identity.generate()
        let sealed = try AnonymousBox.seal(Data("secret".utf8), to: bob.agreementPublicKey, domain: Domain.envelopeBox)
        XCTAssertEqual(sealed.count, 6 + AnonymousBox.overhead)
        XCTAssertEqual(try AnonymousBox.open(sealed, with: bob.agreementKey, domain: Domain.envelopeBox), Data("secret".utf8))
    }

    func testAnonymousBoxOnlyOpensForItsRecipientAndDomain() throws {
        let bob = Identity.generate()
        let eve = Identity.generate()
        let sealed = try AnonymousBox.seal(Data("secret".utf8), to: bob.agreementPublicKey, domain: Domain.envelopeBox)
        XCTAssertThrowsError(try AnonymousBox.open(sealed, with: eve.agreementKey, domain: Domain.envelopeBox))
        XCTAssertThrowsError(try AnonymousBox.open(sealed, with: bob.agreementKey, domain: Domain.inboxBox))

        var tampered = sealed
        tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try AnonymousBox.open(tampered, with: bob.agreementKey, domain: Domain.envelopeBox))
    }

    func testSealingTheSameThingTwiceLooksDifferent() throws {
        let bob = Identity.generate()
        let first = try AnonymousBox.seal(Data("hi".utf8), to: bob.agreementPublicKey, domain: Domain.envelopeBox)
        let second = try AnonymousBox.seal(Data("hi".utf8), to: bob.agreementPublicKey, domain: Domain.envelopeBox)
        XCTAssertNotEqual(first, second)
    }

    func testAttachmentCrypto() throws {
        let photo = Data(repeating: 0xAB, count: 4096)
        let sealed = try AttachmentCrypto.encrypt(photo)
        XCTAssertEqual(sealed.key.count, 32)
        XCTAssertNotEqual(sealed.ciphertext.prefix(64), photo.prefix(64))
        XCTAssertEqual(try AttachmentCrypto.decrypt(sealed.ciphertext, key: sealed.key), photo)
        XCTAssertThrowsError(try AttachmentCrypto.decrypt(sealed.ciphertext, key: Data(count: 32)))
    }
}
