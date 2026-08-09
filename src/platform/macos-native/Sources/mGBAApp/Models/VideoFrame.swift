import Foundation

struct VideoFrame: Equatable {
    let sequence: UInt64
    let width: Int
    let height: Int
    let stride: Int
    let pixels: Data
}

final class VideoFrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latestFrame: VideoFrame?

    func publish(_ frame: VideoFrame) {
        lock.lock()
        latestFrame = frame
        lock.unlock()
    }

    func snapshot() -> VideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    func clear() {
        lock.lock()
        latestFrame = nil
        lock.unlock()
    }
}
