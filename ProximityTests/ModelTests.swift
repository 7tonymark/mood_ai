import XCTest
#if canImport(ProximityCore)
@testable import ProximityCore
#else
@testable import Proximity
#endif

final class PixelAvatarTests: XCTestCase {
    func testHexRoundTrip() {
        let avatar = PixelAvatar.invader
        XCTAssertEqual(avatar.hex.count, 16)
        XCTAssertEqual(PixelAvatar(hex: avatar.hex), avatar)
        XCTAssertNil(PixelAvatar(hex: "nothex"))
    }

    func testRandomAvatarIsSymmetricAndNeverBlank() {
        for _ in 0..<50 {
            let avatar = PixelAvatar.random()
            XCTAssertFalse(avatar.isEmpty)
            for y in 0..<PixelAvatar.size {
                for x in 0..<PixelAvatar.size {
                    XCTAssertEqual(avatar[x, y], avatar[PixelAvatar.size - 1 - x, y])
                }
            }
        }
    }

    func testSubscriptSetsAndClearsSinglePixel() {
        var avatar = PixelAvatar()
        avatar[7, 7] = true
        XCTAssertEqual(avatar.bits, 1 << 63)
        avatar[7, 7] = false
        XCTAssertTrue(avatar.isEmpty)
    }
}

final class ProfileTests: XCTestCase {
    func testSanitize() {
        XCTAssertEqual(Profile.sanitize("ana🙂 maría"), "ANA MARA")
        XCTAssertEqual(Profile.sanitize("abcdefghijklmnop"), "ABCDEFGHIJKL")
    }

    func testNameValidation() {
        XCTAssertTrue(Profile.isValidName("PLAYER ONE!!"))
        XCTAssertFalse(Profile.isValidName(""))
        XCTAssertFalse(Profile.isValidName("   "))
        XCTAssertFalse(Profile.isValidName("lowercase"))
        XCTAssertFalse(Profile.isValidName("WAY TOO LONG NAME"))
    }

    func testAttachmentRefValidation() {
        let good = AttachmentRef(recordName: AttachmentRef.newRecordName(), key: Data(count: 32), width: 640, height: 480)
        XCTAssertTrue(good.isValid)
        var traversal = good
        traversal.recordName = "att-../../friends.json"
        XCTAssertFalse(traversal.isValid)
        var shortKey = good
        shortKey.key = Data(count: 8)
        XCTAssertFalse(shortKey.isValid)
    }

    func testMediaNamesCannotEscapeTheMediaFolder() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalStore(directory: directory)
        store.save(["keep"], to: LocalStore.File.friends)
        store.writeMedia(Data("evil".utf8), "../friends.json")
        XCTAssertEqual(store.load([String].self, from: LocalStore.File.friends), ["keep"])
        XCTAssertNil(store.mediaData("../friends.json"))
    }
}
