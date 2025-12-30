import Foundation
import Darwin

final class JITExecutableMemory {
    private(set) var ptr: UnsafeMutableRawPointer?
    private(set) var capacity: Int = 0
    private(set) var offset: Int = 0

    @inline(__always) func reset() {
        if let p = ptr, capacity > 0 {
            munmap(p, capacity)
        }
        ptr = nil
        capacity = 0
        offset = 0
    }

    deinit { reset() }

    @inline(__always) func ensure(minCapacity: Int = 64 * 1024) {
        if capacity >= minCapacity, ptr != nil { return }

        reset()

        let cap = max(minCapacity, 64 * 1024)
        let p = mmap(nil, cap, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_ANON | MAP_PRIVATE, -1, 0)

        if p == MAP_FAILED {
            ptr = nil
            capacity = 0
            return
        }

        ptr = p
        capacity = cap
        offset = 0
    }

    @inline(__always) func append(_ bytes: [UInt8]) -> UnsafeRawPointer? {
        ensure()
        guard let p = ptr, offset + bytes.count <= capacity else { return nil }
        let dst = p.advanced(by: offset)
        bytes.withUnsafeBytes { src in
            memcpy(dst, src.baseAddress!, bytes.count)
        }
        let start = dst
        offset += bytes.count
        return UnsafeRawPointer(start)
    }
}
