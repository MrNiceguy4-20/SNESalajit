import Foundation

final class EventScheduler {
    struct Event {
        let cycle: Int
        let action: () -> Void
    }

    private var events: [Event] = []

    func reset() { events.removeAll(keepingCapacity: true) }

    func schedule(at cycle: Int, _ action: @escaping () -> Void) {
        events.append(.init(cycle: cycle, action: action))
        events.sort { $0.cycle < $1.cycle }
    }

    func run(dueCycle: Int) {
        while let first = events.first, first.cycle <= dueCycle {
            events.removeFirst()
            first.action()
        }
    }
}
