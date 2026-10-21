# Proximity

A private, close-knit social app for iOS. **You can only add friends you've met in person.**
Friend requests happen over Bluetooth between phones held next to each other, with a
short-lived QR code as a fallback. There's no search, no "people you may know" and no
public profiles. Once you're friends you get a **feed**, **one-to-one chat** and **photos**,
all end-to-end encrypted. Photos can only be **taken live in the app**: it has no access to
your photo library.

The look is a neon arcade cabinet: Press Start 2P pixel type, a starfield over a scrolling
synthwave grid, CRT scanlines, chunky buttons that press down onto their shadows, and an
8×8 pixel avatar you draw yourself.

> "Proximity" is a working title.

## Screens

| Screen | What it does |
| --- | --- |
| **New player** | Pick a name (12 characters, high-score style), one of 6 neon colors, and draw an 8×8 avatar. Your keys are created here, and your card is signed with them. |
| **Feed** | Posts from your friends and you, newest first: text, a live photo, or both. Long-press your own post to delete it for everyone. |
| **New post** | Write something and/or **SNAP A PHOTO**. The camera opens live; there's no library button. |
| **Chat** | Every friend, most recent conversation first, with NEW badges. Text and live photos. |
| **Players** | Your friends as a high-score table (capped at 150). Tap to chat, long-press to remove. |
| **Add player** | Both people open this screen. A radar finds nearby phones with a 5-bar signal meter. ADD unlocks when you're close; you're friends once **both** have pressed it. |
| **QR link** | Fallback: show your code or scan theirs. Codes are signed and expire within about a minute. Both people scan each other. |
| **Continue?** | On a new phone, if your keys haven't arrived through iCloud Keychain yet. |

## Security model

### Identity

- Each player has two keys made on their phone: **Ed25519** for signing and **X25519** for
  encryption (CryptoKit).
- The private keys live in **iCloud Keychain** (marked synchronizable). Apple end-to-end
  encrypts that between your own devices, so a replacement phone gets your identity back.
- A player's id is the SHA-256 hash of their signing key. Nobody can claim your id without
  your private key.

### Cards

A card holds your two public keys, name, color and avatar, signed with your key
(about 150 bytes). Every card is verified when it's received, when it's loaded from disk
and when it comes back from iCloud. A friend's key is **pinned** on first meeting: later
profile updates must be signed by the same key.

### Bluetooth handshake

```
   Phone A                                          Phone B
   ───────                                          ───────
   serves Hello = signed card + fresh nonce(A)      serves Hello = signed card + fresh nonce(B)
   reads B's Hello, verifies card  ───────────────► (hello characteristic)
   (hello characteristic) ◄─────────────────────── reads A's Hello, verifies card

   [A taps ADD, signal ≥ −65 dBm]
   Accept = A's card + B's id + nonce(B)
          + A's mailbox tag sealed to B's key
          + Ed25519 signature over all of it  ─────► B verifies: signature, addressed to B,
                                                     nonce(B) is this session's, opens tag
   [B taps ACCEPT]
   A verifies the same  ◄────────────────────────── Accept from B

   Both accepted → each phone saves the friendship on its own.
```

- **Liveness and no replay:** each phone signs the *other* phone's nonce, which is new
  every time the Add Player screen opens. A recorded acceptance is useless later, or
  against anyone else.
- **Mutual consent:** both phones must accept. The rules live in `HandshakeLedger`,
  which has unit tests.
- **Proximity gate:** ADD unlocks at about −65 dBm or stronger (roughly arm's length).
  Phones weaker than −85 dBm aren't connected to at all.
- **Bystanders learn nothing useful:** only a service UUID is advertised, and the mailbox
  tag inside an Accept is encrypted to the intended friend.
- **Size:** an Accept is about 330 bytes, inside the 512-byte Bluetooth attribute limit.

### QR fallback

The QR code holds your signed card and mailbox tag, plus an expiry. The whole thing is
signed, so the expiry can't be edited. A code is valid for its 30-second window plus 15
seconds, and codes claiming a longer life are rejected even if signed.

### Messages, posts and photos

Everything friends send each other travels as an **envelope**:

1. The payload (a post, a chat message, "delete post", "profile changed" or "unfriend")
   is **signed** with the sender's Ed25519 key.
2. It's **sealed to one recipient**: ephemeral X25519, then HKDF-SHA256, then
   ChaCha20-Poly1305. The sealed envelope carries no sender identity at all.
3. It's dropped into the recipient's **mailbox** in CloudKit's public database. A mailbox
   is just a random 16-byte tag, which you only ever hand to people you add in person.

The recipient decrypts the envelope and checks the signature against the sender's
**pinned** key. It also checks the envelope is addressed to them and that it isn't a
duplicate. Anything from a non-friend, or anything forged, is dropped silently.

- **Photos** are encrypted once with a random 256-bit key and uploaded as a CloudKit
  asset. The key travels only inside the envelopes.
- **Sent copies:** each post and message is also sealed to your own key and put in a
  private archive mailbox. That's how a new phone gets your history back.
- **What the server sees:** that a mailbox tag gets some blobs of some size at some time.
  It never sees names, ids, text or photos. CloudKit does record an app-scoped,
  pseudonymous creator id on each record, so someone who knows your tag (only your friends
  do) could see roughly how many accounts write to you.

### Photos taken on the spot

- The only way to attach a photo is the app's own AVFoundation camera.
- There's no photo-library code in the app, and no `NSPhotoLibraryUsageDescription`, so
  iOS wouldn't let it read the library anyway.
- Photos are resized to 1440 px and re-encoded as JPEG, which drops all metadata
  (location, device, original time).
- They're never saved to the camera roll.

## Architecture

```
Proximity/
  Core/         ← platform-independent, compiles on Linux too, fully unit tested
    Crypto.swift      identity, player ids, AnonymousBox (sealed boxes), photo encryption
    Wire.swift        compact binary encoding for Bluetooth and QR
    Models.swift      signed PlayerCard, Profile, Friend, posts, messages
    Handshake.swift   Hello, AcceptMessage, HandshakeLedger
    QRPayload.swift   signed, expiring QR codes
    Envelope.swift    signed and sealed envelopes
    Backend.swift     CloudBackend protocol (CloudKit on iOS, in-memory in tests)
    AppModel.swift    state, outbox with retries, sync, envelope processing
    LocalStore.swift  on-device JSON and media cache (complete file protection)
  Platform/     CloudKitBackend, KeychainIdentityStore, push setup
  Bluetooth/    NearbyHandshake (CoreBluetooth)
  QR/           QR rendering and scanning
  Features/     Main (tabs), Feed, Chat, Camera, Players, Nearby, QR, Setup, Restore
  Theme/        palette, pixel font, PixelRect, buttons, starfield, scanlines
ProximityTests/ crypto, wire, card, handshake, QR, envelope and end-to-end tests
Package.swift   builds Core + tests with plain `swift test`
```

Only one sync and one upload run at a time; a call made during one waits and then runs
again. Posts and messages show SENDING / FAILED - TAP TO RETRY, and anything unsent is
retried on every sync. The app polls every 15 seconds while open. When it's closed, a
CloudKit push says **INCOMING TRANSMISSION**: the server can't read the envelopes, so it
can't say more.

## Running it

Requirements: Xcode 15 or later, iOS 17+, and **two physical iPhones** for the Bluetooth
handshake. The simulator has no Bluetooth or camera.

```sh
brew install xcodegen
xcodegen generate
open Proximity.xcodeproj     # open the project, not the folder (the folder is also a Swift package)
```

1. **Signing:** select the Proximity target, then Signing & Capabilities. Pick your team
   and change the bundle ID from `com.example.proximity` to one you own.
2. **iCloud and push** need a paid Apple Developer account. Xcode creates the
   `iCloud.<bundle id>` container on first build.
   - **Free account?** In `project.yml`, delete the three entitlement keys (two `icloud`
     keys and `aps-environment`) and remove `CLOUDKIT` from
     `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. Then run `xcodegen generate` again. The app runs,
     but nothing leaves the phone, so feed and chat only show your own posts.
3. **CloudKit schema:** run the app once in development, then in the
   [CloudKit Console](https://icloud.developer.apple.com) add these indexes and deploy the
   schema to production:

   | Database | Record type | Fields | Indexes |
   | --- | --- | --- | --- |
   | Public | `Envelope` | `inbox` (String), `blob` (Bytes) | `inbox`: Queryable; `creationDate`: Queryable + Sortable |
   | Public | `Attachment` | `data` (Asset) | none |
   | Private | `Profile` | `playerID`, `name`, `avatar` (String); `color` (Int64) | none |
   | Private | `Friend` | `card`, `inbox` (Bytes); `addedAt` (Date); `method` (String) | `recordName`: Queryable |

   Also recommended, under Security Roles: remove **World** read access from `Envelope`
   and `Attachment`, so only signed-in app users can fetch them.
4. Run on both phones, open **PLAYERS → + ADD PLAYER** on each, and hold them together.

### Tests

The core logic has tests for crypto, wire formats, signed cards, the handshake, QR codes,
envelopes, and end-to-end scenarios. In those, simulated phones talk through a fake server:
befriending, a post with a photo, chat both ways, forged and replayed envelopes, unfriending,
retries, and restoring onto a new phone.

```sh
swift test                      # on a Mac (macOS 14+), uses CryptoKit
```

On Linux, `swift-crypto` stands in for CryptoKit:

```sh
docker run --rm -v "$PWD":/work -w /work swift:6.0-noble \
  swift test -Xlinker --allow-shlib-undefined   # works around a Swift 6.0 Linux Observation link bug
```

In Xcode, ⌘U runs the same tests against the app target.

## Known limitations / next steps

- **No forward secrecy.** Each envelope uses a fresh ephemeral key, but if someone stole
  your private agreement key they could decrypt envelopes sent to you that are still on the
  server. Next step: a double ratchet for chat, and expiring old envelopes.
- **No key rotation or revocation** for a stolen phone yet.
- **Early messages can be missed.** Mail from someone who isn't your friend yet is dropped,
  for example a post made in the second between their side of the handshake finishing
  and yours.
- **QR is one-directional:** each phone adds the other when it scans, so both people need
  to scan.
- **One-to-one chat only;** no group chats yet.
- **Names are ASCII only,** because of the pixel font. Posts and messages can be in any
  language, including emoji.
- **No app icon** artwork yet (the asset slot is empty).
