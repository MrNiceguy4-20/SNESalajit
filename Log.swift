import Foundation

enum Log {
    static var enabled = true

    static func info(_ s: String) {
        guard enabled else { return }
        NSLog("[INFO] \(s)")
    }

    static func warn(_ s: String) {
        guard enabled else { return }
        NSLog("[WARN] \(s)")
    }
}
