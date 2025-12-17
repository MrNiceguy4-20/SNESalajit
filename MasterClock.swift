import Foundation

final class MasterClock {
    private(set) var masterCycles: Int = 0

    func reset() { masterCycles = 0 }
    func advance(masterCycles: Int) { self.masterCycles &+= masterCycles }
}
