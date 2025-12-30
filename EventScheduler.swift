import Foundation

final class EventScheduler {
    struct Event {
        let cycle: Int
        let action: () -> Void
    }

    private var events: [Event] = []

    @inline(__always) func reset() { events.removeAll(keepingCapacity: true) }

    @inline(__always) func schedule(at cycle: Int, _ action: @escaping () -> Void) {
        events.append(.init(cycle: cycle, action: action))
        events.sort { $0.cycle < $1.cycle }
    }

    @inline(__always) func run(dueCycle: Int) {
        while let first = events.first, first.cycle <= dueCycle {
            events.removeFirst()
            first.action()
        }
    }
}
