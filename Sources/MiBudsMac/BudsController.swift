// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine
import IOBluetooth
import MiBudsCore

// IOBluetooth delivers delegates on the run loop where the channel opens (the main run loop).
@MainActor
final class BudsController: NSObject, ObservableObject,
    @preconcurrency IOBluetoothRFCOMMChannelDelegate
{
    @Published var connected = false
    @Published var connecting = false
    @Published var busy = false
    @Published var status = "Ready to connect"
    @Published var error: String?
    @Published var batteries: [Battery] = []
    @Published var profile: UInt8?
    @Published var lowLatency: Bool?
    @Published var gestures: [UInt8: [UInt8]] = [:]
    @Published var lastUpdate: Date?
    @Published var transport = "No control connection"
    @Published var log: [String] = []
    @Published var autoConnect =
        UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true
    {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "autoConnect") }
    }
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = StreamParser()
    private var auth: Authentication?
    private var counter: UInt8 = 0xa0
    private var generation = UUID()
    private var service: Int?
    private var ticker: Timer?
    private var refreshTimer: Timer?
    private var reconnectTimer: Timer?
    private var connectTimeout: DispatchWorkItem?
    private var pending:
        (
            opcode: UInt8, counter: UInt8, config: UInt16?,
            continuation: CheckedContinuation<[UInt8], Error>
        )?
    private var requestTimeout: DispatchWorkItem?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        if autoConnect { connect() }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoConnect, !self.connecting, !self.connected,
                    self.pairedBuds()?.isConnected() == true
                else { return }
                self.connect()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.disconnect() } }
    }
    private func pairedBuds() -> IOBluetoothDevice? {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first {
            $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "redmi buds 6 play"
        }
    }
    func note(_ message: String) {
        log.append("\(Date().formatted(date: .omitted, time: .standard))  \(message)")
        if log.count > 150 { log.removeFirst(log.count - 150) }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Logs/MiBuds", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? log.joined(separator: "\n").write(
            to: folder.appendingPathComponent("connection.log"), atomically: true, encoding: .utf8)
    }
    func connect() {
        guard !connected, !connecting else { return }
        disconnect()
        error = nil
        guard let peer = pairedBuds() else {
            status = "Pair your earbuds first"
            error = "Open Bluetooth Settings, pair Redmi Buds 6 Play, then connect here."
            return
        }
        device = peer
        connecting = true
        status = "Finding earbud controls…"
        note("Starting SDP discovery for Redmi Buds 6 Play")
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.connecting else { return }
            self.fail(BudsError.timeout)
        }
        connectTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        let result = peer.performSDPQuery(self)
        if result != kIOReturnSuccess { resolveChannel(peer) }
    }
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard connecting, device == self.device, channel == nil else { return }
        note("SDP finished: \(status)")
        resolveChannel(device)
    }
    private func resolveChannel(_ peer: IOBluetoothDevice) {
        let uuids = [
            "0000fd2d00001000800000805f9b34fb", "00001101000010008000008584d01810",
            "0000110100001000800000805f9b34fb",
        ]
        var channelID: BluetoothRFCOMMChannelID = 6
        service = nil
        for (index, text) in uuids.enumerated() {
            let data = stride(from: 0, to: text.count, by: 2).map { offset -> UInt8 in
                let a = text.index(text.startIndex, offsetBy: offset)
                return UInt8(text[a..<text.index(a, offsetBy: 2)], radix: 16)!
            }
            let uuid = IOBluetoothSDPUUID(data: Data(data))
            if let record = peer.getServiceRecord(for: uuid) {
                var resolved: BluetoothRFCOMMChannelID = 0
                if record.getRFCOMMChannelID(&resolved) == kIOReturnSuccess,
                    (1...30).contains(resolved)
                {
                    service = index
                    channelID = resolved
                    break
                }
            }
        }
        transport =
            "RFCOMM \(channelID) · \(service == nil ? "6 Play profile fallback" : "SDP service discovery")"
        note(transport)
        status = "Opening control connection…"
        let result = peer.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
        if result != kIOReturnSuccess {
            fail(
                NSError(
                    domain: "Bluetooth", code: Int(result),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "macOS could not open earbud controls (\(result)). Connect the earbuds in Bluetooth Settings and close other companion apps."
                    ]))
        }
    }
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        guard connecting, rfcommChannel == channel else { return }
        guard status == kIOReturnSuccess else {
            fail(
                NSError(
                    domain: "Bluetooth", code: Int(status),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The Bluetooth control connection failed (\(status)). Try reconnecting your earbuds."
                    ]))
            return
        }
        note("RFCOMM opened")
        if let service {
            self.status = "Authenticating earbuds…"
            note(service == 0 ? "Authenticating control service" : "Authenticating serial service")
            let session = Authentication(mode: service == 0 ? .command : .raw)
            auth = session
            session.send = { [weak self] bytes in
                guard let self else { throw BudsError.disconnected }
                try self.send(bytes)
            }
            do { try session.start() } catch {
                fail(error)
                return
            }
            ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in do { try self?.auth?.tick() } catch { self?.fail(error) } }
            }
        } else {
            didBecomeReady()
        }
    }
    private func didBecomeReady() {
        connectTimeout?.cancel()
        ticker?.invalidate()
        ticker = nil
        connected = true
        connecting = false
        status = "Connected"
        error = nil
        note("Control session ready")
        let token = generation
        Task { @MainActor in
            if service == nil {
                // Preserve the upstream 6 Play direct-session setup, only for the unknown-UUID fallback.
                do { try send([0xfe, 0xdc, 0xba, 0x04, 0x51, 0, 3, 0, 3, 1, 0xef]) } catch {
                    fail(error)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard generation == token, connected else { return }
            refresh()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    private func send(_ bytes: [UInt8]) throws {
        guard let channel, channel.isOpen() else { throw BudsError.disconnected }
        var bytes = bytes
        let result = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        guard result == kIOReturnSuccess else { throw BudsError.disconnected }
    }
    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard rfcommChannel == channel, let dataPointer else { return }
        var bytes = Array(
            UnsafeBufferPointer(
                start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        if let auth, !auth.ready {
            do {
                bytes = try auth.feed(bytes)
                if auth.ready { didBecomeReady() }
            } catch {
                fail(error)
                return
            }
        }
        for packet in parser.feed(bytes) {
            if let levels = BudsCodec.batteries(in: packet.payload) {
                batteries = levels
                lastUpdate = Date()
                note(
                    "Battery received: "
                        + levels.map { $0.percent.map { "\($0)%" } ?? "unavailable" }.joined(
                            separator: ", "))
            }
            // Acknowledge notifications requesting a response using the peer's sequence.
            if packet.flags & 0xc0 == 0xc0, let seq = packet.payload.first,
                ![0x50, 0x51].contains(packet.opcode)
            {
                try? send(Packet(flags: 4, opcode: packet.opcode, payload: [0, seq]).bytes)
            }
            guard let request = pending, packet.flags & 0x80 == 0,
                packet.opcode == request.opcode, packet.payload.count >= 2,
                packet.payload[1] == request.counter
            else { continue }
            if packet.payload[0] != 0 {
                complete(.failure(BudsError.rejected(packet.payload[0])))
                continue
            }
            let data = Array(packet.payload.dropFirst(2))
            if let config = request.config, request.opcode == 0xf3 {
                do {
                    guard try BudsCodec.records(data)[config] != nil else { continue }
                } catch {
                    complete(.failure(error))
                    continue
                }
            }
            complete(.success(data))
        }
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel == channel else { return }
        note("Control connection closed")
        disconnect()
        status = "Disconnected"
    }
    private func exchange(_ opcode: UInt8, config: UInt16? = nil, body: [UInt8]) async throws
        -> [UInt8]
    {
        guard connected, pending == nil else { throw BudsError.disconnected }
        let sequence = counter
        counter &+= 1
        return try await withCheckedThrowingContinuation { continuation in
            pending = (opcode, sequence, config, continuation)
            let work = DispatchWorkItem { [weak self] in self?.complete(.failure(BudsError.timeout))
            }
            requestTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
            do { try send(BudsCodec.request(opcode: opcode, counter: sequence, body: body)) } catch
            { complete(.failure(error)) }
        }
    }
    private func complete(_ result: Result<[UInt8], Error>) {
        let request = pending
        pending = nil
        requestTimeout?.cancel()
        requestTimeout = nil
        request?.continuation.resume(with: result)
    }
    private func read(_ config: UInt16) async throws -> [UInt8] {
        let data = try await exchange(
            0xf3, config: config, body: [UInt8(config >> 8), UInt8(config & 255)])
        guard let value = try BudsCodec.records(data)[config] else { throw BudsError.invalidPacket }
        return value
    }
    private func write(_ config: UInt16, _ value: [UInt8]) async throws {
        _ = try await exchange(
            0xf2, config: config,
            body: [UInt8(value.count + 2), UInt8(config >> 8), UInt8(config & 255)] + value)
    }
    func refresh() {
        guard connected, !busy else { return }
        busy = true
        error = nil
        let token = generation
        Task { @MainActor in
            defer { if token == generation { busy = false } }
            do { _ = try await exchange(2, body: [255, 255, 255, 255]) } catch {
                report(error, token: token)
            }
            guard token == generation else { return }
            do {
                let value = try await read(7)
                guard token == generation else { return }
                guard value.count == 1 else { throw BudsError.invalidPacket }
                profile = value[0]
            } catch {
                if token == generation {
                    profile = nil
                    report(error, token: token)
                }
            }
            guard token == generation else { return }
            do {
                let value = try await read(47)
                guard token == generation else { return }
                guard value.count == 1, value[0] <= 1 else { throw BudsError.invalidPacket }
                lowLatency = value[0] == 1
            } catch {
                if token == generation {
                    lowLatency = nil
                    report(error, token: token)
                }
            }
            guard token == generation else { return }
            do {
                let value = try await read(2)
                guard token == generation else { return }
                gestures = try BudsCodec.gestures(value)
            } catch {
                if token == generation {
                    gestures = [:]
                    report(error, token: token)
                }
            }
            if token == generation { note("Finished refreshing earbud settings") }
        }
    }
    func setProfile(_ value: UInt8) { change(config: 7, value: [value]) }
    func setLatency(_ value: Bool) { change(config: 47, value: [value ? 1 : 0]) }
    func setGesture(_ gesture: UInt8, side: Int, action: UInt8) {
        guard gestures[gesture] != nil, BudsCodec.allowedActions(gesture).contains(action) else {
            return
        }
        change(
            config: 2, value: [gesture, side == 0 ? action : 255, side == 1 ? action : 255],
            gesture: (gesture, side, action))
    }
    private func change(config: UInt16, value: [UInt8], gesture: (UInt8, Int, UInt8)? = nil) {
        guard connected, !busy else { return }
        busy = true
        error = nil
        let token = generation
        Task { @MainActor in
            defer { if token == generation { busy = false } }
            do {
                try await write(config, value)
                let actual = try await read(config)
                guard token == generation else { return }
                if let (id, side, action) = gesture {
                    let assignments = try BudsCodec.gestures(actual)
                    gestures = assignments
                    guard assignments[id]?[side] == action else { throw BudsError.unconfirmed }
                } else {
                    guard actual.count == 1 else { throw BudsError.invalidPacket }
                    if config == 7 { profile = actual[0] } else { lowLatency = actual[0] == 1 }
                    guard actual == value else { throw BudsError.unconfirmed }
                }
                note("Setting saved and verified on earbuds")
            } catch {
                if token == generation {
                    if config == 7 { profile = nil }
                    if config == 47 { lowLatency = nil }
                    if config == 2 { gestures = [:] }
                    report(error, token: token)
                }
            }
        }
    }
    private func report(_ error: Error, token: UUID) {
        guard generation == token else { return }
        self.error = error.localizedDescription
        note(error.localizedDescription)
    }
    private func fail(_ error: Error) {
        let message = error.localizedDescription
        disconnect()
        self.error = message
        status = "Connection needs attention"
        note(message)
    }
    func disconnect() {
        generation = UUID()
        connectTimeout?.cancel()
        requestTimeout?.cancel()
        ticker?.invalidate()
        refreshTimer?.invalidate()
        auth = nil
        complete(.failure(BudsError.disconnected))
        let oldChannel = channel
        channel = nil
        oldChannel?.setDelegate(nil)
        oldChannel?.close()
        connected = false
        connecting = false
        busy = false
        profile = nil
        lowLatency = nil
        gestures = [:]
        batteries = []
        lastUpdate = nil
        parser = StreamParser()
        status = "Disconnected"
    }
    func openBluetoothSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}
