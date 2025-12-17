import Foundation

var globalLogHandler: ((String, String) -> Void)?
enum Log {
    static func info(_ s: String) {
        globalLogHandler?(s, "INFO")
    }

    static func warn(_ s: String) {
        globalLogHandler?(s, "WARN")
    }
}
