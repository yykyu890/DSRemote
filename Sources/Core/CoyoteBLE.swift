import Foundation
import CoreBluetooth
import Combine

/// 郊狼 3.0 直连：iPhone 当 BLE 中心，每 100ms 发一帧 B0。
///
/// 服务 0x180C，写 0x150A，通知 0x150B。
/// 一帧 20 字节：0xB0 | 序号(4bit)+模式(4bit) | A强度 | B强度 |
///              A频率×4 | A脉冲×4 | B频率×4 | B脉冲×4
@MainActor
final class CoyoteBLE: NSObject, ObservableObject {
    @Published private(set) var state = CoyoteState()
    @Published private(set) var found: [(name: String, id: UUID)] = []
    @Published private(set) var scanning = false
    @Published private(set) var errorText = ""

    /// 强度上限（低于设备上限，防止手滑）
    var maxStrength = 40

    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var timer: Timer?
    private var seq: UInt8 = 0
    private var pulsesA: [(Int, Int)] = Array(repeating: (10, 0), count: 4)
    private var pulsesB: [(Int, Int)] = Array(repeating: (10, 0), count: 4)
    private var playUntil: Date?

    private let serviceUUID = CBUUID(string: "180C")
    private let writeUUID = CBUUID(string: "150A")
    private let notifyUUID = CBUUID(string: "150B")
    private let deviceName = "47L121000"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - 扫描 / 连接

    func startScan() {
        guard central.state == .poweredOn else {
            errorText = "蓝牙不可用（检查系统蓝牙是否打开）"
            return
        }
        found = []
        scanning = true
        errorText = ""
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        // 8 秒后自动停
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        central.stopScan()
        scanning = false
    }

    func connect(_ id: UUID) {
        let target = discovered[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let target else {
            errorText = "找不到这个设备，重新扫描一次"
            return
        }
        peripheral = target
        target.delegate = self
        central.connect(target, options: nil)
        errorText = ""
    }

    func disconnect() {
        stopMotor()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        state.connected = false
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 控制

    func setStrength(_ channel: String, value: Int, mode: String = "set") {
        let capped = max(0, min(maxStrength, value))
        let modeBits: UInt8 = mode == "inc" ? 0b01 : mode == "dec" ? 0b10 : 0b11
        var a: UInt8 = 0b00
        var b: UInt8 = 0b00
        var strengthA = state.strengthA
        var strengthB = state.strengthB
        if channel == "A" {
            a = modeBits
            if mode == "set" { strengthA = capped }
        } else {
            b = modeBits
            if mode == "set" { strengthB = capped }
        }
        sendFrame(modeA: a, modeB: b, strengthA: strengthA, strengthB: strengthB)
        if mode == "set" {
            if channel == "A" { state.strengthA = capped } else { state.strengthB = capped }
        }
    }

    func play(_ channel: String, waveform: Waveform, seconds: Double) {
        let pulses = waveform.pulses
        if channel == "A" { pulsesA = pulses } else { pulsesB = pulses }
        playUntil = Date().addingTimeInterval(max(1, seconds))
        state.playing = "\(channel) \(waveform.label)"
    }

    func stopMotor() {
        pulsesA = Array(repeating: (10, 0), count: 4)
        pulsesB = Array(repeating: (10, 0), count: 4)
        playUntil = nil
        state.playing = ""
        if state.connected {
            sendFrame(modeA: 0, modeB: 0,
                      strengthA: state.strengthA, strengthB: state.strengthB)
        }
    }

    // MARK: - 帧

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        if let until = playUntil, Date() > until {
            pulsesA = Array(repeating: (10, 0), count: 4)
            pulsesB = Array(repeating: (10, 0), count: 4)
            playUntil = nil
            state.playing = ""
        }
        sendFrame(modeA: 0, modeB: 0,
                  strengthA: state.strengthA, strengthB: state.strengthB)
    }

    private func sendFrame(modeA: UInt8, modeB: UInt8, strengthA: Int, strengthB: Int) {
        guard let peripheral, let writeChar else { return }
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0xB0
        frame[1] = (seq << 4) | ((modeA & 0b11) << 2) | (modeB & 0b11)
        frame[2] = UInt8(max(0, min(200, strengthA)))
        frame[3] = UInt8(max(0, min(200, strengthB)))
        for index in 0..<4 {
            let (fa, ia) = index < pulsesA.count ? pulsesA[index] : (10, 0)
            frame[4 + index] = UInt8(max(10, min(240, fa)))
            frame[8 + index] = UInt8(max(0, min(100, ia)))
            let (fb, ib) = index < pulsesB.count ? pulsesB[index] : (10, 0)
            frame[12 + index] = UInt8(max(10, min(240, fb)))
            frame[16 + index] = UInt8(max(0, min(100, ib)))
        }
        seq = (seq &+ 1) % 16
        let data = Data(frame)
        peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
    }
}

// MARK: - 代理

extension CoyoteBLE: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state != .poweredOn {
                self.errorText = "蓝牙不可用：\(central.state.rawValue)"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        Task { @MainActor in
            let isCoyote = name.contains("47L121000")
            if !isCoyote { return }
            if !self.found.contains(where: { $0.id == peripheral.identifier }) {
                self.found.append((name: name.isEmpty ? "未命名" : name,
                                   id: peripheral.identifier))
                self.discovered[peripheral.identifier] = peripheral
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.state.connected = true
            self.errorText = ""
            peripheral.discoverServices([self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.state.connected = false
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == CBUUID(string: "180C") {
            peripheral.discoverCharacteristics([CBUUID(string: "150A"),
                                                CBUUID(string: "150B")],
                                               for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(string: "150A") {
                Task { @MainActor in
                    self.writeChar = characteristic
                    self.startTimer()
                }
            }
            if characteristic.uuid == CBUUID(string: "150B") {
                peripheral.setNotifyValue(true, for: characteristic)
                Task { @MainActor in self.notifyChar = characteristic }
            }
        }
    }
}
