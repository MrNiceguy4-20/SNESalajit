import Foundation

final class FaultRecorder: @unchecked Sendable {

    struct FaultEvent: Sendable {
        let wallClock: Date
        let component: String
        let message: String
        let pc24: UInt32?
        let masterCycle: UInt64?
        let scanline: Int?
        let dot: Int?
    }

    private let lock = NSLock()
    private var lastEvent: FaultEvent?
    private var ring: [FaultEvent] = []
    private let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = max(8, capacity)
        self.ring.reserveCapacity(self.capacity)
    }

    func record(component: String,
                message: String,
                pc24: UInt32? = nil,
                masterCycle: UInt64? = nil,
                scanline: Int? = nil,
                dot: Int? = nil) {
        let e = FaultEvent(
            wallClock: Date(),
            component: component,
            message: message,
            pc24: pc24,
            masterCycle: masterCycle,
            scanline: scanline,
            dot: dot
        )
        lock.lock()
        defer { lock.unlock() }
        lastEvent = e
        ring.append(e)
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }
    }

    func last() -> FaultEvent? {
        lock.lock()
        defer { lock.unlock() }
        return lastEvent
    }

    func recent() -> [FaultEvent] {
        lock.lock()
        defer { lock.unlock() }
        return ring
    }
}
