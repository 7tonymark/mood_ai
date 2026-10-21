# Proximity

A private, close-knit social app for iOS. **You can only add friends you've met in person.**
Friend requests happen over Bluetooth between phones held next to each other, with a
short-lived QR code as a fallback. There's no search, no "people you may know" and no
public profiles.

The look is a neon arcade cabinet: Press Start 2P pixel type, a starfield over a
scrolling synthwave grid, CRT scanlines, chunky buttons that press down onto their
shadows, and an 8×8 pixel avatar you draw yourself.

> "Proximity" is a working title.

## What's in this first build

| Screen | What it does |
| --- | --- |
| **New player** | Pick a name (12 characters, high-score style), one of 6 neon colors, and draw an 8×8 avatar, or hit RANDOM for a symmetric "space invader". |
| **Players** | Your friends as a high-score table: rank, avatar, name, the date you met and how you met (BT / QR). Long-press to remove someone. Capped at 150 friends. |
| **Add player** | Both people open this screen. A radar finds nearby phones, with a 5-bar signal meter. When you're close enough, ADD sends your card. Once you've *both* pressed it, you're friends. |
| **QR link** | Fallback: show your code, or scan theirs. Codes refresh every 30 seconds and expire shortly after, so a forwarded screenshot is useless. Both people scan each other. |

## How the Bluetooth handshake works

Every phone on the Add player screen is both a BLE **peripheral** (advertising) and a
**central** (scanning). Only a service UUID is advertised; names never go out over the air
until two phones connect.

```
   Phone A                                         Phone B
   ───────                                         ───────
   advertise service ◄──── scan finds A ────────── scan
   scan ──────────── scan finds B ────────────────► advertise service
   connect + read B's card ──────────────────────► (card characteristic)
   (card characteristic) ◄─────────────────────── connect + read A's card

   [A taps ADD, signal ≥ −65 dBm]
   write A's card ───────────────────────────────► accept characteristic
                                                   B marks "they accepted"
   [B taps ACCEPT, signal ≥ −65 dBm]
   accept characteristic ◄─────────────────────── write B's card
   A marks "they accepted"

   A: I accepted + they accepted → friends     B: same → friends
```

- **Mutual consent:** each phone saves the friendship only when it has both sent its card
  and received the other's. The rules live in `HandshakeLedger`, which has unit tests.
- **Proximity gate:** ADD unlocks only at around −65 dBm or stronger (about arm's length).
  Phones further than about −85 dBm aren't even connected to.
- **Foreground only:** the radio is on only while the Add player screen is open.
  (iOS heavily limits background BLE advertising anyway.)
- **What's shared:** a `PlayerCard`, which holds a random player ID, name, color and
  avatar (about 90 bytes). No Apple ID, phone number or email.

## Storage

- **On device:** the profile and friend list are JSON files in Application Support, with
  complete file protection.
- **iCloud (CloudKit, private database only):** the friend list is mirrored to the user's
  own private iCloud database, so it survives a lost or replaced phone. On a new phone,
  setup is skipped if a profile is found in iCloud. Nothing is written to a public database,
  so there's nothing anyone else can query.

## Running it

Requirements: Xcode 15 or later, iOS 17+, and **two physical iPhones** to try the
Bluetooth handshake. The simulator has no Bluetooth or camera. The rest of the UI runs
fine in the simulator.

```sh
brew install xcodegen
xcodegen generate
open Proximity.xcodeproj
```

Then in Xcode:

1. Select the **Proximity** target, then **Signing & Capabilities**. Pick your team and
   change the bundle ID from `com.example.proximity` to one you own.
2. **CloudKit** needs a paid Apple Developer account. Xcode creates the
   `iCloud.<bundle id>` container on first build.
   - In the CloudKit Console, add a **Queryable** index on `recordName` for the `Friend`
     record type, or the friend-list fetch is rejected.
   - **Free account?** In `project.yml`, delete the two `com.apple.developer.icloud-*`
     entitlement keys and remove `CLOUDKIT` from `SWIFT_ACTIVE_COMPILATION_CONDITIONS`,
     then run `xcodegen generate` again. The app then works on-device only.
3. Run on both phones, open **+ ADD PLAYER** on each, and hold them together.

Tests: `⌘U` in Xcode, or
`xcodebuild test -scheme Proximity -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Project layout

```
Proximity/
  App/          entry point, AppModel (state + sync), haptics
  Bluetooth/    NearbyHandshake (CoreBluetooth), HandshakeLedger (pure rules)
  QR/           expiring QR payload, generator, AVFoundation scanner
  Storage/      LocalStore (JSON), CloudSync (CloudKit private DB)
  Models/       PlayerCard, Profile, Friend, PixelAvatar
  Theme/        palette, pixel font, PixelRect, buttons, starfield, scanlines
  Features/     Home, Setup, Nearby, QR screens
  Resources/    Press Start 2P font (SIL Open Font License, see OFL.txt)
ProximityTests/ avatar, card, ledger, QR and model tests
```

## Known limitations / next steps

- **Cards aren't signed.** Someone with a custom BLE tool standing right next to you
  could present a fake card. Next step: a per-device key pair, with each card signed and
  the key pinned on first meeting.
- **QR is one-directional.** Each phone adds the other when it scans, so both people
  need to scan. A half-done exchange leaves the friendship one-sided.
- **No content yet.** There's no feed, chat or photos, so there's nothing to do with a
  friend after adding them. That's the next big product decision. CloudKit sharing
  (`CKShare`) would keep shared content inside the same private, iCloud-only model.
- **Names are ASCII only**, because the pixel font has no other glyphs.
- **No app icon** artwork yet (the asset slot is empty).
