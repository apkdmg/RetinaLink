import Foundation

struct RenderTiming {
    let sequence: UInt64
    let width, height: Int
    let queueMS, unpackMS, uploadMS, drawableMS, gpuMS, totalMS: Double
}

// Counter windows advance on a timer, including while the desktop is idle.
// Callers serialize access (the Viewer uses a lock because GPU callbacks are asynchronous).
struct RateWindow {
    private var start: Double
    var frames = 0, bytes = 0
    init(now: Double = ProcessInfo.processInfo.systemUptime) { start = now }
    mutating func take(now: Double = ProcessInfo.processInfo.systemUptime) -> (fps: Double, mbps: Double) {
        let elapsed = max(0.001, now-start)
        let result = (Double(frames)/elapsed, Double(bytes)*8/elapsed/1e6)
        frames = 0; bytes = 0; start = now
        return result
    }
}

final class ViewerStatistics {
    private let lock = NSLock()
    private var rate = RateWindow()
    private var width = 0, height = 0, count = 0
    private var queue = 0.0, unpack = 0.0, upload = 0.0, drawable = 0.0, gpu = 0.0, total = 0.0
    private var assembly = 0.0, assembled = 0
    private var presentationRate = RateWindow()
    private var drawableWidth = 0, drawableHeight = 0
    private var lastPresentation = 0.0, presentationGap = 0.0
    private var longGaps = 0
    func presented(width: Int, height: Int, time: Double) {
        guard time > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        presentationRate.frames += 1; drawableWidth = width; drawableHeight = height
        if lastPresentation > 0 {
            let gap = (time-lastPresentation)*1000
            presentationGap = max(presentationGap, gap)
            if gap > 25 { longGaps += 1 }
        }
        lastPresentation = time
    }
    func receivedBody(in milliseconds: Double) {
        lock.lock(); defer { lock.unlock() }; assembly += milliseconds; assembled += 1
    }
    func received(_ bytes: Int) {
        lock.lock(); defer { lock.unlock() }; rate.bytes += bytes
    }
    func completed(_ t: RenderTiming) {
        lock.lock(); defer { lock.unlock() }
        rate.frames += 1; count += 1; width = t.width; height = t.height
        queue += t.queueMS; unpack += t.unpackMS; upload += t.uploadMS
        drawable += t.drawableMS; gpu += t.gpuMS; total += t.totalMS
    }
    func report() -> String {
        lock.lock(); defer { lock.unlock() }
        let rates = rate.take(), presented = presentationRate.take(), n = Double(max(1,count))
        let headline = String(format:"%d × %d · %.1f rendered updates/s · %.1f Mbps",width,height,rates.fps,rates.mbps)
        let timing = count == 0 ? "Idle — no completed frames in this interval." : String(format:"Average ms: queue %.1f · unpack %.1f · upload setup %.1f\nDrawable wait %.1f · GPU %.1f · receiver total %.1f",queue/n,unpack/n,upload/n,drawable/n,gpu/n,total/n)
        let transport = assembled == 0 ? "" : String(format:"\nNetwork body assembly %.1f ms (before render timings)",assembly/Double(assembled))
        count = 0; queue = 0; unpack = 0; upload = 0; drawable = 0; gpu = 0; total = 0; assembly = 0; assembled = 0
        let presentation = String(format:"\nPresentation %.1f fps · drawable %d × %d · max gap %.1f ms · gaps >25 ms %d",presented.fps,drawableWidth,drawableHeight,presentationGap,longGaps)
        presentationGap = 0; longGaps = 0
        return headline + "\n" + timing + transport + presentation
    }
}
