#if HOST
import Foundation
import CoreVideo

// One frame being encoded plus one replaceable pending frame. No unbounded
// capture queue, and intermediate desktop states can be discarded before encoding.
final class CaptureMailbox {
    struct Input {let image:CVPixelBuffer;let id:UInt64;let displayTime:Double?}
    private let lock = NSLock()
    private var enabled = false, scheduled = false
    private var pending: Input?
    private var complete = 0, inactive = 0, replaced = 0
    func start() { lock.lock(); enabled = true; lock.unlock() }
    func stop() { lock.lock(); enabled = false; pending = nil; scheduled = false; lock.unlock() }
    func idle() { lock.lock(); if enabled { inactive += 1 }; lock.unlock() }
    func offer(_ image: CVPixelBuffer,id:UInt64=0,displayTime:Double?=nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return false }
        complete += 1
        if pending != nil { replaced += 1 }
        pending = Input(image:image,id:id,displayTime:displayTime)
        if scheduled { return false }
        scheduled = true; return true
    }
    func take() -> CVPixelBuffer? {
        takeInput()?.image
    }
    func takeInput() -> Input? {
        lock.lock(); defer { lock.unlock() }
        guard enabled, let image = pending else { scheduled = false; return nil }
        pending = nil; return image
    }
    func counts() -> (complete: Int, inactive: Int, replaced: Int) {
        lock.lock(); defer { lock.unlock() }
        let result = (complete, inactive, replaced)
        complete = 0; inactive = 0; replaced = 0
        return result
    }
}
#endif
