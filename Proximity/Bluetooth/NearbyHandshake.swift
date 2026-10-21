import CoreBluetooth
import Foundation
import Observation

enum BLE {
    static let service = CBUUID(string: "6E2B0001-6B5F-4C7A-9C1E-2F8A3D4B5C60")
    /// Readable: the advertising phone's `Hello` (signed card + session nonce).
    static let helloCharacteristic = CBUUID(string: "6E2B0002-6B5F-4C7A-9C1E-2F8A3D4B5C60")
    /// Writable: a visitor writes a signed `AcceptMessage` here to say "I accept you".
    static let acceptCharacteristic = CBUUID(string: "6E2B0003-6B5F-4C7A-9C1E-2F8A3D4B5C60")

    /// Phones weaker than this are ignored entirely; we don't even connect.
    static let connectRSSI = -85
    /// Accepting someone requires the phones to be within roughly an arm's length.
    static let closeRSSI = -65
    /// A peer disappears from the list after this long without a signal reading.
    static let staleAfter: TimeInterval = 8
    /// CoreBluetooth never times out a connection attempt, so we give up on our own.
    static let connectTimeout: TimeInterval = 10

    static func bars(for rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        case (-55)...: return 5
        case -65 ..< -55: return 4
        case -72 ..< -65: return 3
        case -79 ..< -72: return 2
        case -86 ..< -79: return 1
        default: return 0
        }
    }
}

/// Finds nearby players and runs the mutual-accept handshake over Bluetooth Low Energy.
///
/// Every phone on the "Add player" screen is both a peripheral (serving its `Hello`) and a
/// central (scanning for others). Tapping ADD writes a signed `AcceptMessage`, bound to the other
/// phone's nonce, to that phone. Once both phones have accepted each other, each side saves the
/// friendship on its own. Nothing runs in the background: the radio is only on while the
/// screen is open, and a new nonce is made every time it opens.
@Observable
final class NearbyHandshake: NSObject {
    enum Status: Equatable {
        case starting, searching, poweredOff, unauthorized, unsupported
    }

    struct Peer: Identifiable, Equatable {
        let id: UUID
        var card: PlayerCard
        var rssi: Int?
        var iAccepted: Bool
        var theyAccepted: Bool
        var completed: Bool
        var sending: Bool
        var canSend: Bool

        var isClose: Bool { (rssi ?? Int.min) >= BLE.closeRSSI }
    }

    private(set) var status: Status = .starting
    private(set) var peers: [Peer] = []

    @ObservationIgnored var onFriendAdded: ((Introduction) -> Void)?

    @ObservationIgnored private let identity: Identity
    @ObservationIgnored private let myCard: PlayerCard
    @ObservationIgnored private let hello: Hello
    @ObservationIgnored private let helloData: Data
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var advertiser: CBPeripheralManager?
    @ObservationIgnored private var ledger = HandshakeLedger()
    /// Outgoing connections, keyed by `CBPeripheral.identifier`.
    @ObservationIgnored private var links: [UUID: Link] = [:]
    /// Smoothed signal strength, keyed by player id.
    @ObservationIgnored private var signal: [UUID: (rssi: Int, seen: Date)] = [:]
    @ObservationIgnored private var sending: Set<UUID> = []
    @ObservationIgnored private var timer: Timer?

    private struct Link {
        let peripheral: CBPeripheral
        let startedAt = Date()
        /// What they served us: their verified card and this session's nonce.
        var hello: Hello?
        var accept: CBCharacteristic?
    }

    init(identity: Identity, card: PlayerCard) {
        let hello = Hello(card: card, nonce: Hello.newNonce())
        self.identity = identity
        self.myCard = card
        self.hello = hello
        self.helloData = hello.encoded
        super.init()
    }

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
        advertiser = CBPeripheralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let central {
            central.stopScan()
            for link in links.values {
                central.cancelPeripheralConnection(link.peripheral)
            }
        }
        advertiser?.stopAdvertising()
        advertiser?.removeAllServices()
        links.removeAll()
        central = nil
        advertiser = nil
    }

    /// Sends my signed acceptance to a nearby player. Ignored unless they're close enough.
    func accept(_ playerID: UUID) {
        guard let reading = signal[playerID], reading.rssi >= BLE.closeRSSI,
              let link = links.values.first(where: { $0.hello?.card.id == playerID }),
              let peerHello = link.hello,
              let characteristic = link.accept,
              !sending.contains(playerID),
              let message = try? AcceptMessage.make(identity: identity, card: myCard, to: peerHello) else { return }
        sending.insert(playerID)
        link.peripheral.writeValue(message, for: characteristic, type: .withResponse)
        rebuild()
    }

    // MARK: - Bookkeeping

    private func tick() {
        let now = Date()
        for (id, link) in links {
            if link.peripheral.state == .connected {
                link.peripheral.readRSSI()
            }
            // Drop attempts that never got as far as reading a Hello; the next advertisement retries.
            if link.hello == nil, now.timeIntervalSince(link.startedAt) > BLE.connectTimeout {
                central?.cancelPeripheralConnection(link.peripheral)
                links[id] = nil
            }
        }
        rebuild()
    }

    private func record(rssi: Int, for playerID: UUID) {
        guard rssi < 0 else { return } // 127 means "unavailable"
        let smoothed = signal[playerID].map { Int((Double($0.rssi) * 0.6 + Double(rssi) * 0.4).rounded()) } ?? rssi
        signal[playerID] = (smoothed, Date())
        rebuild()
    }

    private func complete(_ introduction: Introduction) {
        Haptics.success()
        onFriendAdded?(introduction)
    }

    private func rebuild() {
        let now = Date()
        let writable = Set(links.values.compactMap { $0.accept != nil ? $0.hello?.card.id : nil })
        peers = ledger.entries.compactMap { element -> Peer? in
            let (id, entry) = element
            let reading = signal[id]
            let fresh = reading.map { now.timeIntervalSince($0.seen) < BLE.staleAfter } ?? false
            guard fresh || entry.theyAccepted || entry.completed else { return nil }
            return Peer(
                id: id,
                card: entry.card,
                rssi: fresh ? reading?.rssi : nil,
                iAccepted: entry.iAccepted,
                theyAccepted: entry.theyAccepted,
                completed: entry.completed,
                sending: sending.contains(id),
                canSend: writable.contains(id)
            )
        }
        // Sort by name, not signal, so rows don't jump around while people hold their phones.
        .sorted { ($0.card.name, $0.id.uuidString) < ($1.card.name, $1.id.uuidString) }
    }
}

// MARK: - Scanning for others (central role)

extension NearbyHandshake: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = .searching
            central.scanForPeripherals(
                withServices: [BLE.service],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        case .poweredOff:
            status = .poweredOff
            links.removeAll()
            sending.removeAll()
            rebuild()
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            status = .starting
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi < 0, rssi >= BLE.connectRSSI else { return }
        if let link = links[peripheral.identifier] {
            if let playerID = link.hello?.card.id {
                record(rssi: rssi, for: playerID)
            }
        } else {
            links[peripheral.identifier] = Link(peripheral: peripheral)
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BLE.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        links[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let playerID = links[peripheral.identifier]?.hello?.card.id {
            sending.remove(playerID)
        }
        // Forgetting the link lets the next advertisement reconnect.
        links[peripheral.identifier] = nil
        rebuild()
    }
}

extension NearbyHandshake: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == BLE.service }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([BLE.helloCharacteristic, BLE.acceptCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case BLE.helloCharacteristic:
                peripheral.readValue(for: characteristic)
            case BLE.acceptCharacteristic:
                links[peripheral.identifier]?.accept = characteristic
            default:
                break
            }
        }
        rebuild()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLE.helloCharacteristic else { return }
        // Hello.decode verifies the card's signature; forged or garbled cards never show up.
        guard error == nil, let data = characteristic.value,
              let theirHello = Hello.decode(data), theirHello.card.id != identity.id else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        links[peripheral.identifier]?.hello = theirHello
        ledger.discovered(theirHello.card)
        peripheral.readRSSI()
        rebuild()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLE.acceptCharacteristic,
              let playerID = links[peripheral.identifier]?.hello?.card.id else { return }
        sending.remove(playerID)
        if error == nil, let introduction = ledger.markIAccepted(playerID) {
            complete(introduction)
        }
        rebuild()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, let playerID = links[peripheral.identifier]?.hello?.card.id else { return }
        record(rssi: RSSI.intValue, for: playerID)
    }
}

// MARK: - Being found (peripheral role)

extension NearbyHandshake: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        let helloCharacteristic = CBMutableCharacteristic(
            type: BLE.helloCharacteristic, properties: [.read], value: nil, permissions: [.readable]
        )
        let acceptCharacteristic = CBMutableCharacteristic(
            type: BLE.acceptCharacteristic, properties: [.write], value: nil, permissions: [.writeable]
        )
        let service = CBMutableService(type: BLE.service, primary: true)
        service.characteristics = [helloCharacteristic, acceptCharacteristic]
        peripheral.removeAllServices()
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        // Only the service UUID is advertised. Cards are shared over a connection.
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLE.service]])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLE.helloCharacteristic else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }
        guard request.offset <= helloData.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = helloData.subdata(in: request.offset..<helloData.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        guard requests.allSatisfy({ $0.characteristic.uuid == BLE.acceptCharacteristic }) else {
            peripheral.respond(to: first, withResult: .requestNotSupported)
            return
        }
        // Long writes arrive as several requests with increasing offsets.
        var data = Data()
        for request in requests.sorted(by: { $0.offset < $1.offset }) {
            if let value = request.value {
                data.append(value)
            }
        }
        // Checks the signature, that it's addressed to me, and that it carries this session's nonce.
        guard let introduction = AcceptMessage.open(data, identity: identity, myNonce: hello.nonce),
              introduction.card.id != identity.id else {
            peripheral.respond(to: first, withResult: .unlikelyError)
            return
        }
        peripheral.respond(to: first, withResult: .success)
        if let completed = ledger.markTheyAccepted(introduction) {
            complete(completed)
        }
        rebuild()
    }
}
