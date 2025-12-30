import Foundation

enum Hex {
    @inline(__always) static func u8(_ v: UInt8) -> String { String(format: "$%02X", v) }
    @inline(__always) static func u16(_ v: UInt16) -> String { String(format: "$%04X", v) }
    @inline(__always) static func u24(bank: UInt8, addr: UInt16) -> String {
        String(format: "$%02X:%04X", bank, addr)
    }
}

struct CPU65816DebugSnapshot: Sendable {
    let a: u16
    let x: u16
    let y: u16
    let sp: u16
    let dp: u16
    let db: u8
    let pb: u8
    let pc: u16
    let p: u8
    let emulationMode: Bool
    let mem8: Bool
    let index8: Bool
    let nmiLine: Bool
    let irqLine: Bool
    let useJIT: Bool

    init(cpu: CPU65816) {
        let r = cpu.r
        a = r.a; x = r.x; y = r.y
        sp = r.sp; dp = r.dp
        db = r.db; pb = r.pb; pc = r.pc
        p = r.p.rawValue
        emulationMode = r.emulationMode
        mem8 = r.p.contains(.mem8)
        index8 = r.p.contains(.index8)
        nmiLine = cpu.nmiLine
        irqLine = cpu.irqLine
        useJIT = cpu.useJIT
    }
}


struct APUHandshakeEvent: Sendable {
    enum Direction: Sendable { case cpuToApu, apuToCpu }
    let direction: Direction
    let port: Int   // 0..3
    let value: u8
}


struct APUDebugSnapshot: Sendable {
    let spcA: u8
    let spcX: u8
    let spcY: u8
    let spcSP: u8
    let spcPC: u16
    let spcPSW: u8
    let spcHalted: Bool
    let spcHaltReason: String
    let iplEnabled: Bool
    let spcJITEnabled: Bool
    let cpuToApu: [u8]
    let apuToCpu: [u8]

    // Handshake debug
    let cpuToApuPendingMask: u8
    let lastCpuToApuWrite: [u8]
    let lastApuToCpuWrite: [u8]
    let recentPortEvents: [APUHandshakeEvent]
}

struct EmulatorDebugSnapshot: Sendable {
    let wallClock: Date
    let isRunning: Bool
    let romName: String?
    let romSHA1: String?
    let cpu: CPU65816DebugSnapshot
    let cpuLastInstruction: CPU65816.InstructionTraceEntry?
    let cpuTrace: [CPU65816.InstructionTraceEntry]
    let bus: Bus.BusDebugState
    let ppu: PPU.PPUDebugState
    let ppuFramebufferSize: (width: Int, height: Int)
    let spc: APUDebugSnapshot
    let recentLogs: [String]
    let logs: [String]

}
