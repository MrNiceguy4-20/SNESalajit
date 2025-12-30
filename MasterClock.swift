import Foundation

final class MasterClock {
    static let masterHz: Double = 21_477_272.0
    static let masterCyclesPerCPUCycle: Int = 6

    private(set) var masterCycles: Int = 0
    private var cpuMasterRemainder: Int = 0

    @inline(__always) func reset() {
        masterCycles = 0
        cpuMasterRemainder = 0
    }

    @inline(__always) func advance(masterCycles: Int) {
        self.masterCycles &+= masterCycles
    }

    @inline(__always) func cpuCycles(forMasterCycles masterCycles: Int) -> Int {
        cpuMasterRemainder += masterCycles
        let cpuCycles = cpuMasterRemainder / Self.masterCyclesPerCPUCycle
        cpuMasterRemainder = cpuMasterRemainder % Self.masterCyclesPerCPUCycle
        return cpuCycles
    }
}
