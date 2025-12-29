import Foundation

final class Bus {
    @inline(__always) func isIOBank(_ bank: u8) -> Bool {
        return bank == 0x00 || bank == 0x80
    }


    weak var cpu: CPU65816?
    weak var ppu: PPU?
    weak var ppuOwner: Emulator?
    var apu: APU?
    private(set) var cartridge: Cartridge?
    private var vectorMappingOverride: Cartridge.Mapping? = nil
    private var wram = WRAM()
    private var wramPortAddr: Int = 0
    var video = VideoTiming()
    private var dotCycleAcc: Int = 0
    let irq = InterruptController()
    private let dma = DMAEngine()
    private let joypads = JoypadIO()
    private var autoJoy1: u16 = 0xFFFF
    private var autoJoy2: u16 = 0xFFFF
    private var autoJoypadStartDelayDots: Int = 0
    private var mdmaen: u8 = 0
    private var hdmaen: u8 = 0
    private var openBus: u8 = 0x00
    private var dmaActive: Bool = false
    private var dmaStallMasterCycles: Int = 0
    private var hvbjoyReadCount: Int = 0
    private var lastHVBJOY: u8 = 0x00
    private var rdnmiReadCount: Int = 0
    private var timeupReadCount: Int = 0
    private var nmitimenWriteCount: Int = 0
    private var lastNMITIMEN: u8 = 0x00
    private var lastRDNMI: u8 = 0x00
    private var lastTIMEUP: u8 = 0x00

    struct BusDebugState {
        let scanline: Int
        let dot: Int
        let inVBlank: Bool
        let isVisibleScanline: Bool
        let isHBlank: Bool
        let nmiLine: Bool
        let irqLine: Bool
        let hIrqEnable: Bool
        let vIrqEnable: Bool
        let autoJoypadEnable: Bool
        let mdmaEnabled: u8
        let hdmaEnabled: u8
        let dmaStallCycles: Int
        let autoJoypadBusy: Bool
        let autoJoy1: u16
        let autoJoy2: u16
        let autoJoypadBusyDots: Int
        let hvbjoyReadCount: Int
        let lastHVBJOY: u8
        let rdnmiReadCount: Int
        let timeupReadCount: Int
        let nmitimenWriteCount: Int
        let lastNMITIMEN: u8
        let lastRDNMI: u8
        let lastTIMEUP: u8
        let irq: InterruptController.InterruptDebugState
    }

    func debugSnapshot() -> BusDebugState {
        BusDebugState(
            scanline: video.scanline,
            dot: video.dot,
            inVBlank: video.inVBlank,
            isVisibleScanline: video.isVisibleScanline,
            isHBlank: video.isHBlank,
            nmiLine: irq.nmiLine,
            irqLine: irq.irqLine,
            hIrqEnable: irq.hIrqEnable,
            vIrqEnable: irq.vIrqEnable,
            autoJoypadEnable: irq.autoJoypadEnable,
            mdmaEnabled: mdmaen,
            hdmaEnabled: hdmaen,
            dmaStallCycles: dmaStallMasterCycles,
            autoJoypadBusy: video.autoJoypadBusy,
            autoJoy1: autoJoy1,
            autoJoy2: autoJoy2,
            autoJoypadBusyDots: video.autoJoypadBusyDots,
            hvbjoyReadCount: hvbjoyReadCount,
            lastHVBJOY: lastHVBJOY,
            rdnmiReadCount: rdnmiReadCount,
            timeupReadCount: timeupReadCount,
            nmitimenWriteCount: nmitimenWriteCount,
            lastNMITIMEN: lastNMITIMEN,
            lastRDNMI: lastRDNMI,
            lastTIMEUP: lastTIMEUP,
            irq: irq.debugSnapshot()
        )
    }

    func reset() {
        wram.reset()
        ppu?.reset()
        wramPortAddr = 0
        video.reset()
        irq.reset()
        dotCycleAcc = 0
        dma.reset()
        joypads.reset()
        autoJoy1 = 0xFFFF
        autoJoy2 = 0xFFFF
        mdmaen = 0
        hdmaen = 0
        openBus = 0x00
        dmaStallMasterCycles = 0
        hvbjoyReadCount = 0
        lastHVBJOY = 0x00
        rdnmiReadCount = 0
        timeupReadCount = 0
        lastRDNMI = 0x02
        lastTIMEUP = 0x00
        nmitimenWriteCount = 0
        lastNMITIMEN = 0x00
        autoJoypadStartDelayDots = 0
        cpu?.setNMI(false)
        cpu?.setIRQ(false)
    }

    func insertCartridge(_ cart: Cartridge) {
        cartridge = cart
        vectorMappingOverride = nil
        let cur = cart.mapping
        let other: Cartridge.Mapping = (cur == .hiROM) ? .loROM : (cur == .loROM ? .hiROM : .unknown)

        func mappingLooksPlausible(_ mapping: Cartridge.Mapping) -> Bool {
            guard mapping != .unknown else { return false }
            guard let v = readVector16(cart, mapping: mapping, addr: 0xFFFC) else { return false }
            if v == 0x0000 || v == 0xFFFF { return false }
            if v < 0x8000 { return false }
            guard let op = readCartridgeByte(cart, mapping: mapping, bank: 0x00, addr: v & 0xFFFF) else { return false }
            if op == 0xFF { return false }
            switch op {
            case 0x00, 0x02, 0x40, 0x60, 0x6B, 0xDB, 0x82, 0x42: return false
            default: return true
            }
        }
        if cur != .unknown && other != .unknown {
            if !mappingLooksPlausible(cur) && mappingLooksPlausible(other) {
                vectorMappingOverride = other
                Log.warn("ROMLoader mapping \(cur) produced implausible reset vector/opcode; overriding vector mapping to \(other).", component: .system)
            }
        }
    }

    private func romOffsetForMapping(_ mapping: Cartridge.Mapping, bank: u8, addr: u16) -> Int? {
        let b = Int(bank)
        if b == 0x7E || b == 0x7F { return nil }

        switch mapping {
        case .loROM:
            // 00-3F,80-BF: 8000-FFFF -> ROM
            // 40-7D,C0-FF: 0000-7FFF -> ROM (mirror)
            if (b <= 0x3F) || (b >= 0x80 && b <= 0xBF) {
                guard addr >= 0x8000 else { return nil }
                return ((b & 0x3F) * 0x8000) + Int(addr - 0x8000)
            }
            if (b >= 0x40 && b <= 0x7D) || (b >= 0xC0 && b <= 0xFF) {
                guard addr < 0x8000 else { return nil }
                return ((b & 0x3F) * 0x8000) + Int(addr)
            }
            return nil

        case .hiROM:
            // 00-3F,80-BF: 8000-FFFF -> ROM
            // 40-7D,C0-FF: 0000-FFFF -> ROM
            if (b <= 0x3F) || (b >= 0x80 && b <= 0xBF) {
                guard addr >= 0x8000 else { return nil }
                return ((b & 0x3F) * 0x10000) + Int(addr)
            }
            if (b >= 0x40 && b <= 0x7D) || (b >= 0xC0 && b <= 0xFF) {
                return ((b & 0x3F) * 0x10000) + Int(addr)
            }
            return nil

        case .unknown:
            return nil
        }
    }

    private func readCartridgeByte(_ cart: Cartridge, mapping: Cartridge.Mapping, bank: u8, addr: u16) -> u8? {
        guard let off0 = romOffsetForMapping(mapping, bank: bank, addr: addr) else { return nil }
        let count = cart.rom.count
        guard count > 0 else { return nil }
        let off = off0 >= 0 ? (off0 % count) : nil
        guard let o = off else { return nil }
        return cart.rom[o]
    }


    private func readVector16(_ cart: Cartridge, mapping: Cartridge.Mapping, addr: u16) -> u16? {
        guard let lo = readCartridgeByte(cart, mapping: mapping, bank: 0x00, addr: addr),
              let hi = readCartridgeByte(cart, mapping: mapping, bank: 0x00, addr: addr &+ 1) else { return nil }
        return u16(lo) | (u16(hi) << 8)
    }

    func consumeDMAStall(masterCycles maxMasterCycles: Int) -> Int {
        if dmaStallMasterCycles <= 0 { return 0 }
        let c = min(maxMasterCycles, dmaStallMasterCycles)
        dmaStallMasterCycles -= c
        return c
    }

    var isDMASstallingCPU: Bool { dmaStallMasterCycles > 0 }

    func step(masterCycles: Int) {
        dotCycleAcc += masterCycles
        while dotCycleAcc >= VideoTiming.masterCyclesPerDot {
            dotCycleAcc -= VideoTiming.masterCyclesPerDot
            tickDot()
        }
        cpu?.setNMI(irq.nmiLine)
        cpu?.setIRQ(irq.irqLine)
    }

    private func tickDot() {
        irq.reapplyLatchedNMITIMEN(dot: video.dot, scanline: video.scanline)
        irq.pollHVMatch(dot: video.dot, scanline: video.scanline)
        video.stepDot()
        if video.dot == 0 {
            if hdmaen != 0, video.isVisibleScanline { dma.hdmaStep(mask: hdmaen, bus: self) }
        }
        if video.consumeDidEnterVBlank() {
            irq.onEnterVBlank(dot: video.dot, scanline: video.scanline)
            if hdmaen != 0 { dma.hdmaInit(mask: hdmaen, bus: self) }
            if irq.autoJoypadEnable { autoJoypadStartDelayDots = 75 }
            ppu?.onEnterVBlank()
        }
        if video.consumeDidLeaveVBlank() {
            irq.onLeaveVBlank(dot: video.dot, scanline: video.scanline)
            ppu?.onLeaveVBlank()
        }
        if autoJoypadStartDelayDots > 0 {
            autoJoypadStartDelayDots -= 1
            if autoJoypadStartDelayDots == 0 { beginAutoJoypad() }
        }
    }

    func read8_physical(bank: u8, addr: u16) -> u8 {
        // Physical reads are used for things like debug/trace and vector plausibility checks.
        // They should reflect the same mapping rules as normal CPU reads, including open-bus behavior.

        if bank == 0x7E || bank == 0x7F {
            let v = wram.read8(offset: (Int(bank - 0x7E) << 16) | Int(addr))
            openBus = v
            return v
        }

        if isIOBank(bank), addr < 0x2000 {
            let v = wram.read8(offset: Int(addr))
            openBus = v
            return v
        }

        if isIOBank(bank), (MMIO.isMMIO(addr) || addr == 0x4016 || addr == 0x4017) {
            let v = read8_mmio(addr)
            openBus = v
            return v
        }

        if let c = cartridge {
            let mapping = vectorMappingOverride ?? c.mapping
            if let v = readCartridgeByte(c, mapping: mapping, bank: bank, addr: addr) {
                openBus = v
                return v
            }
            let v = c.read8(bank: bank, addr: addr)
            openBus = v
            return v
        }

        return openBus
    }


    func read8_dma(bank: u8, addr: u16) -> u8 {
        dmaActive = true
        let v = read8(bank: bank, addr: addr)
        dmaActive = false
        return v
    }

    func read8(bank: u8, addr: u16) -> u8 {
        if !dmaActive {
            if let cpu = cpu, cpu.isWaiting && !cpu.nmiPending && !cpu.irqLine { return openBus }
        }

        if bank == 0x7E || bank == 0x7F {
            let o = (Int(bank - 0x7E) << 16) | Int(addr)
            let v = wram.read8(offset: o)
            openBus = v
            return v
        }

        if isIOBank(bank), addr < 0x2000 {
            let v = wram.read8(offset: Int(addr))
            openBus = v
            return v
        }
        if isIOBank(bank), addr >= 0x2000, addr < 0x8000,
           !(MMIO.isMMIO(addr) || addr == 0x4016 || addr == 0x4017) {
            return openBus
        }
        if isIOBank(bank), (MMIO.isMMIO(addr) || addr == 0x4016 || addr == 0x4017) {
            let v = read8_mmio(addr)
            openBus = v
            return v
        }
        if let c = cartridge {
            if let ov = vectorMappingOverride, isIOBank(bank), addr >= 0xFF00 {
                if let v = readCartridgeByte(c, mapping: ov, bank: bank, addr: addr) {
                    openBus = v
                    return v
                }
            }
            let mapping = vectorMappingOverride ?? c.mapping
            if let v = readCartridgeByte(c, mapping: mapping, bank: bank, addr: addr) {
                openBus = v
                return v
            }
            let v = c.read8(bank: bank, addr: addr)
            openBus = v
            return v
        }
        return openBus
    }

    func write8(bank: u8, addr: u16, value: u8) {
        openBus = value

        if isIOBank(bank), addr < 0x2000 {
            if MMIO.isMMIO(addr) || addr == 0x4016 || addr == 0x4017 {
                write8_mmio(addr, value: value)
                return
            }
            wram.write8(offset: Int(addr & 0x1FFF), value: value)
            return
        }

        if bank == 0x7E || bank == 0x7F {
            let o = (Int(bank - 0x7E) << 16) | Int(addr)
            wram.write8(offset: o, value: value)
            return
        }

        if isIOBank(bank), (MMIO.isMMIO(addr) || addr == 0x4016 || addr == 0x4017) {
            write8_mmio(addr, value: value)
            return
        }
        cartridge?.write8(bank: bank, addr: addr, value: value)
    }

    func read8_mmio(_ addr: u16) -> u8 {
        var v: u8 = openBus

        // APU ports must be checked before the broad PPU $2100-$21FF range.
        if addr >= 0x2140 && addr <= 0x2143 {
            v = apu?.cpuReadPort(Int(addr - 0x2140)) ?? openBus

        } else if addr >= 0x2100 && addr <= 0x21FF {
            v = ppu?.readRegister(addr: addr, openBus: openBus, video: video) ?? openBus

        } else if addr == 0x2180 {
            v = wram.read8(offset: wramPortAddr)
            wramPortAddr = (wramPortAddr + 1) & 0x1FFFF

        } else if addr >= 0x4200 && addr <= 0x421F {
            v = readCPUReg(addr)

        } else if addr >= 0x4300 && addr <= 0x437F {
            let ch = Int((addr - 0x4300) / 0x10)
            let reg = Int((addr - 0x4300) % 0x10)
            v = dma.readReg(channel: ch, reg: reg)

        } else if addr == 0x4016 {
            v = joypads.read4016()
        } else if addr == 0x4017 {
            v = joypads.read4017()
        }

        openBus = v
        return v
    }

    func write8_mmio(_ addr: u16, value: u8) {
        openBus = value

        if addr == 0x4016 {
            joypads.writeStrobe(value)
            return
        }

        if addr == 0x2180 {
            wram.write8(offset: wramPortAddr, value: value)
            wramPortAddr = (wramPortAddr + 1) & 0x1FFFF
            return
        }
        if addr == 0x2181 {
            wramPortAddr = (wramPortAddr & 0x1FF00) | Int(value)
            return
        }
        if addr == 0x2182 {
            wramPortAddr = (wramPortAddr & 0x100FF) | (Int(value) << 8)
            return
        }
        if addr == 0x2183 {
            wramPortAddr = (wramPortAddr & 0x0FFFF) | ((Int(value) & 0x01) << 16)
            return
        }

        // APU ports must be checked before the broad PPU $2100-$21FF range.
        if addr >= 0x2140 && addr <= 0x2143 {
            apu?.cpuWritePort(Int(addr - 0x2140), value: value)
            return
        }

        if addr >= 0x2100 && addr <= 0x21FF {
            ppu?.writeRegister(addr: addr, value: value, openBus: &openBus, video: video)
            return
        }

        if addr >= 0x4200 && addr <= 0x421F {
            writeCPUReg(addr, value: value)
            return
        }

        if addr >= 0x4300 && addr <= 0x437F {
            let ch = Int((addr - 0x4300) / 0x10)
            let reg = Int((addr - 0x4300) % 0x10)
            dma.writeReg(channel: ch, reg: reg, value: value)
            return
        }
    }



    private func beginAutoJoypad() {
        joypads.latch()
        let (w1, w2) = joypads.latchedWords()
        autoJoy1 = w1
        autoJoy2 = w2
        video.autoJoypadBusyDots = 1056
    }

    private func readCPUReg(_ addr: u16) -> u8 {
        switch addr {
        case 0x4210:
            rdnmiReadCount &+= 1
            let v = irq.readRDNMI(dot: video.dot, scanline: video.scanline)
            lastRDNMI = v
            return v
        case 0x4211:
            timeupReadCount &+= 1
            let v = irq.readTIMEUP(dot: video.dot, scanline: video.scanline)
            lastTIMEUP = v
            return v
        case 0x4212:
            var v = openBus & 0x3E
            if video.inVBlank { v |= 0x80 }
            if video.isHBlank { v |= 0x40 }
            if video.autoJoypadBusy { v |= 0x01 }
            hvbjoyReadCount &+= 1
            lastHVBJOY = v
            irq.logHVBJOYRead(value: v, dot: video.dot, scanline: video.scanline)
            return v
        case 0x4218: return u8(truncatingIfNeeded: autoJoy1)
        case 0x4219: return u8(truncatingIfNeeded: autoJoy1 >> 8)
        case 0x421A: return u8(truncatingIfNeeded: autoJoy2)
        case 0x421B: return u8(truncatingIfNeeded: autoJoy2 >> 8)
        default: return openBus
        }
    }

    private func writeCPUReg(_ addr: u16, value: u8) {
        switch addr {
        case 0x4200:
            nmitimenWriteCount &+= 1
            lastNMITIMEN = value
            irq.setNMITIMEN(value, video: video, dot: video.dot, scanline: video.scanline)
        case 0x4207: irq.hTime = (irq.hTime & 0x100) | Int(value)
        case 0x4208: irq.hTime = (irq.hTime & 0x0FF) | ((Int(value) & 1) << 8)
        case 0x4209: irq.vTime = (irq.vTime & 0x100) | Int(value)
        case 0x420A: irq.vTime = (irq.vTime & 0x0FF) | ((Int(value) & 1) << 8)
        case 0x420B:
            mdmaen = value
            let stall = dma.start(mask: value, bus: self)
            _ = consumeDMAStall(masterCycles: stall)
            mdmaen = 0
            return
        case 0x420C: hdmaen = value
            return
        default: break
        }
    }
}
