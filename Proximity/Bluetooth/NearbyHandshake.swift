import CoreBluetooth
import Foundation
import Observation

enum BLE {
    static let service = CBUUID(string: "6E2B0001-6B5F-4C7A-9C1E-2F8A3D4B5C60")
    /// Readable: the advertising phone's `PlayerCard`.
    static let cardCharacteristic = CBUUID(string: "6E2B0002-6B5F-4C7A-9C1E-2F8A3D4B5C60")
    /// Writable: a visitor writes *their* card here to say "I accept you".
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
        case -55...: return 5
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
/// Every phone on the "Add player" screen is both a peripheral (advertising its card) and a
/// central (scanning for others). Tapping ADD writes my card to the other phone; once both
/// phones have written to each other, each side saves the friendship on its own.
/// Nothing runs in the background: the radio is only on while that screen is open.
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

    @ObservationIgnored var onFriendAdded: ((PlayerCard) -> Void)?

    @ObservationIgnored private let myCard: PlayerCard
    @ObservationIgnored private let cardData: Data
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
        var playerID: UUID?
        var accept: CBCharacteristic?
    }

    init(myCard: PlayerCard) {
        self.myCard = myCard
        self.cardData = myCard.encoded()
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

    /// Sends my card to a nearby player. Ignored unless they're close enough.
    func accept(_ playerID: UUID) {
        guard let reading = signal[playerID], reading.rssi >= BLE.closeRSSI,
              let link = links.values.first(where: { $0.playerID == playerID }),
              let characteristic = link.accept,
              !sending.contains(playerID) else { return }
        sending.insert(playerID)
        link.peripheral.writeValue(cardData, for: characteristic, type: .withResponse)
        rebuild()
    }

    // MARK: - Bookkeeping

    private func tick() {
        let now = Date()
        for (id, link) in links {
            if link.peripheral.state == .connected {
                link.peripheral.readRSSI()
            }
            // Drop attempts that never got as far as reading a card; the next advertisement retries.
            if link.playerID == nil, now.timeIntervalSince(link.startedAt) > BLE.connectTimeout {
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

    private func complete(_ card: PlayerCard) {
        Haptics.success()
        onFriendAdded?(card)
    }

    private func rebuild() {
        let now = Date()
        let writable = Set(links.values.compactMap { $0.accept != nil ? $0.playerID : nil })
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
            if let playerID = link.playerID {
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
        if let playerID = links[peripheral.identifier]?.playerID {
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
        peripheral.discoverCharacteristics([BLE.cardCharacteristic, BLE.acceptCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case BLE.cardCharacteristic:
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
        guard characteristic.uuid == BLE.cardCharacteristic else { return }
        guard error == nil, let data = characteristic.value,
              let card = PlayerCard.decode(data), card.id != myCard.id else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        links[peripheral.identifier]?.playerID = card.id
        ledger.discovered(card)
        peripheral.readRSSI()
        rebuild()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLE.acceptCharacteristic,
              let playerID = links[peripheral.identifier]?.playerID else { return }
        sending.remove(playerID)
        if error == nil, let card = ledger.markIAccepted(playerID) {
            complete(card)
        }
        rebuild()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, let playerID = links[peripheral.identifier]?.playerID else { return }
        record(rssi: RSSI.intValue, for: playerID)
    }
}

// MARK: - Being found (peripheral role)

extension NearbyHandshake: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        let card = CBMutableCharacteristic(
            type: BLE.cardCharacteristic, properties: [.read], value: nil, permissions: [.readable]
        )
        let accept = CBMutableCharacteristic(
            type: BLE.acceptCharacteristic, properties: [.write], value: nil, permissions: [.writeable]
        )
        let service = CBMutableService(type: BLE.service, primary: true)
        service.characteristics = [card, accept]
        peripheral.removeAllServices()
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        // Only the service UUID is advertised. Names and ids are shared over a connection.
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [BLE.service]])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BLE.cardCharacteristic else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }
        guard request.offset <= cardData.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = cardData.subdata(in: request.offset..<cardData.count)
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
        guard let card = PlayerCard.decode(data), card.id != myCard.id else {
            peripheral.respond(to: first, withResult: .unlikelyError)
            return
        }
        peripheral.respond(to: first, withResult: .success)
        if let completed = ledger.markTheyAccepted(card) {
            complete(completed)
        }
        rebuild()
    }
}
