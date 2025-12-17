import Foundation

enum LogComponent: String {
    case system = "SYSTEM"
    case cpu = "CPU"
    case ppu = "PPU"
    case apu = "APU"
}

enum LogLevel: String, CaseIterable, Identifiable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"

    var id: String { rawValue }

    private var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }

    init?(levelString: String) {
        self.init(rawValue: levelString.uppercased())
    }
}

var globalLogHandler: ((String, LogLevel) -> Void)?

enum Log {
    private static func emit(_ message: String, level: LogLevel, component: LogComponent) {
        globalLogHandler?("[\(component.rawValue)] \(message)", level)
    }

    static func debug(_ s: String, component: LogComponent = .system) {
        emit(s, level: .debug, component: component)
    }

    static func info(_ s: String, component: LogComponent = .system) {
        emit(s, level: .info, component: component)
    }

    static func warn(_ s: String, component: LogComponent = .system) {
        emit(s, level: .warn, component: component)
    }
}
