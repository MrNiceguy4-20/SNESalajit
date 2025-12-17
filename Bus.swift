import Foundation

/// SNES address space decoding (Phase 3–4).
final class Bus {
    weak var cpu: CPU65816?
    weak var ppu: PPU?
    weak var apu: APU?

    private(set) var cartridge: Cartridge?
    private var wram = WRAM()

    // Timing + interrupts + DMA
    var video = VideoTiming()
    private var dotCycleAcc: Int = 0

    private let irq = InterruptController()
    private let dma = DMAEngine()

    // Joypad I/O ($4016/$4017)
    private let joypads = JoypadIO()

    private var mdmaen: u8 = 0
    private var hdmaen: u8 = 0
    private var openBus: u8 = 0xFF

    /// Master-cycle stall remaining due to MDMA
    private var dmaStallMasterCycles: Int = 0

    func reset() {
        wram.reset()
        video.reset()
        dotCycleAcc = 0

        irq.reset()
        dma.reset()
        joypads.reset()

        mdmaen = 0
        hdmaen = 0
        openBus = 0xFF
        dmaStallMasterCycles = 0

        cpu?.setNMI(false)
        cpu?.setIRQ(false)
    }

    func insertCartridge(_ cart: Cartridge) {
        cartridge = cart
    }

    // MARK: - DMA stall

    func consumeDMAStall(masterCycles maxMasterCycles: Int) -> Int {
        if dmaStallMasterCycles <= 0 { return 0 }
        let c = min(maxMasterCycles, dmaStallMasterCycles)
        dmaStallMasterCycles -= c
        return c
    }

    var isDMAStallingCPU: Bool { dmaStallMasterCycles > 0 }

    // MARK: - Timekeeping

    func step(masterCycles: Int) {
        dotCycleAcc += masterCycles

        video.didEnterVBlank = false
        video.didLeaveVBlank = false

        while dotCycleAcc >= VideoTiming.masterCyclesPerDot {
            dotCycleAcc -= VideoTiming.masterCyclesPerDot
            tickDot()
        }

        cpu?.setNMI(irq.nmiLine)
        cpu?.setIRQ(irq.irqLine)
    }

    private func tickDot() {
        video.dot += 1
        if video.autoJoypadBusyDots > 0 { video.autoJoypadBusyDots -= 1 }
        irq.pollHVMatch(dot: video.dot, scanline: video.scanline)

        if video.dot >= VideoTiming.dotsPerScanline {
            video.dot = 0
            tickScanline()
        }
    }

    private func tickScanline() {
        video.scanline += 1
        if video.scanline >= VideoTiming.totalScanlines {
            video.scanline = 0
        }

        let nowVBlank = (video.scanline >= VideoTiming.visibleScanlines)
        if nowVBlank && !video.inVBlank {
            video.inVBlank = true
            video.didEnterVBlank = true
            irq.onEnterVBlank()
            if irq.autoJoypadEnable { beginAutoJoypad() }
            ppu?.onEnterVBlank()
        } else if !nowVBlank && video.inVBlank {
            video.inVBlank = false
            video.didLeaveVBlank = true
            irq.onLeaveVBlank()
            ppu?.onLeaveVBlank()
        }
    }

    // MARK: - Bus read/write

    func read8(bank: u8, addr: u16) -> u8 {
        if bank == 0x7E || bank == 0x7F {
            let o = (Int(bank - 0x7E) << 16) | Int(addr)
            let v = wram.read8(offset: o)
            openBus = v
            return v
        }

        if isIOBank(bank), (MMIO.isMMIO(addr) || addr == 0x4016 || addr == 0x4017) {
            let v = read8_mmio(addr)
            openBus = v
            return v
        }

        if let c = cartridge {
            let v = c.read8(bank: bank, addr: addr)
            openBus = v
            return v
        }

        return openBus
    }

    func write8(bank: u8, addr: u16, value: u8) {
        openBus = value

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

    private func isIOBank(_ bank: u8) -> Bool {
        (bank & 0x7F) <= 0x3F
    }

    // MARK: - MMIO

    func read8_mmio(_ addr: u16) -> u8 {
        // Joypads
        if addr == 0x4016 { return (openBus & 0xFE) | joypads.read4016() }
        if addr == 0x4017 { return (openBus & 0xFE) | joypads.read4017() }

        // APU ports ($2140-$2143)
        if addr >= 0x2140 && addr <= 0x2143 {
            return apu?.cpuReadPort(Int(addr - 0x2140)) ?? 0x00
        }

        // PPU
        if addr >= 0x2100 && addr <= 0x21FF {
            let v = ppu?.readRegister(addr: addr, openBus: openBus, video: video) ?? openBus
            return v
        }

        // CPU/IRQ
        if addr >= 0x4200 && addr <= 0x421F {
            return readCPUReg(addr)
        }

        // DMA
        if addr >= 0x4300 && addr <= 0x437F {
            let ch = Int((addr - 0x4300) / 0x10)
            let reg = Int((addr - 0x4300) % 0x10)
            return dma.readReg(channel: ch, reg: reg)
        }

        return openBus
    }

    func write8_mmio(_ addr: u16, value: u8) {
        openBus = value

        if addr == 0x4016 {
            joypads.writeStrobe(value)
            return
        }

        // APU ports ($2140-$2143)
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

    // MARK: - Auto joypad

    private func beginAutoJoypad() {
        joypads.latch()
        video.autoJoypadBusyDots = 256
    }

    private func readCPUReg(_ addr: u16) -> u8 {
        switch addr {
        case 0x4210: return irq.readRDNMI()
        case 0x4211: return irq.readTIMEUP()
        case 0x4212: return SPCTimers.hvbjoy(video: video)
        default:     return openBus
        }
    }

    private func writeCPUReg(_ addr: u16, value: u8) {
        switch addr {
        case 0x4200:
            irq.nmiEnable = (value & 0x80) != 0
            irq.hvIrqEnable = (value & 0x30) != 0
            irq.autoJoypadEnable = (value & 0x01) != 0
        case 0x4207:
            irq.hTime = (irq.hTime & 0x100) | Int(value)
        case 0x4208:
            irq.hTime = (irq.hTime & 0x0FF) | ((Int(value) & 1) << 8)
        case 0x4209:
            irq.vTime = (irq.vTime & 0x100) | Int(value)
        case 0x420A:
            irq.vTime = (irq.vTime & 0x0FF) | ((Int(value) & 1) << 8)
        case 0x420B:
            mdmaen = value
            dmaStallMasterCycles &+= dma.start(mask: value, bus: self)
        case 0x420C:
            hdmaen = value
        case 0x420D:
            break
        default:
            break
        }
    }
}
