import Foundation

enum LogComponent: String {
    case system = "SYSTEM"
    case cpu = "CPU"
    case ppu = "PPU"
    case apu = "APU"
}

var globalLogHandler: ((String, String) -> Void)?

enum Log {
    private static func emit(_ message: String, level: String, component: LogComponent) {
        globalLogHandler?("[\(component.rawValue)] \(message)", level)
    }

    static func debug(_ s: String, component: LogComponent = .system) {
        emit(s, level: "DEBUG", component: component)
    }

    static func info(_ s: String, component: LogComponent = .system) {
        emit(s, level: "INFO", component: component)
    }

    static func warn(_ s: String, component: LogComponent = .system) {
        emit(s, level: "WARN", component: component)
    }
}
