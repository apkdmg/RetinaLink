import Foundation

struct RenderTiming {
    let sequence: UInt64
    let width, height: Int
    let queueMS, unpackMS, uploadMS, drawableMS, gpuMS, totalMS: Double
    var submissionMS=0.0, callbackMS=0.0, presentMS=0.0
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

// Driver timestamps can repeat, be zero for displayed frames, or arrive out of
// order. This measures API timing anomalies, not physical display FPS. History
// is bounded; callbacks older than retired history are counted as stale instead
// of making an old timestamp look new again.
struct PresentationCounter {
    struct Sample {
        let uniquePerSecond:Double, positivePerSecond:Double, unique:Int, maxGapMS:Double, longGaps:Int
        let repeated:Int, zero:Int, invalid:Int, reordered:Int, stale:Int, lateGap:Int
    }
    private let capacity:Int, reorderWindow:Double
    private var rate:RateWindow
    private var positiveRate:RateWindow
    private var seen=Set<Double>(), history:[Double]=[], pending:[Double]=[]
    private var retiredThrough=0.0, latest=0.0, lastGapTime=0.0, maxGapMS=0.0
    private var longGaps=0, repeated=0, zero=0, invalid=0, reordered=0, stale=0, lateGap=0
    var retainedTimestampCount:Int {history.count}
    init(now:Double=ProcessInfo.processInfo.systemUptime,capacity:Int=256,reorderWindow:Double=0.1) {
        precondition(capacity>0 && reorderWindow.isFinite && reorderWindow>=0)
        self.capacity=capacity;self.reorderWindow=reorderWindow;rate=RateWindow(now:now);positiveRate=RateWindow(now:now)
    }
    @discardableResult mutating func record(_ time:Double)->Bool {
        if time==0 {zero += 1;return false}
        guard time.isFinite && time>0 else {invalid += 1;return false}
        positiveRate.frames += 1
        guard !seen.contains(time) else {repeated += 1;return false}
        guard time>retiredThrough else {stale += 1;return false}
        seen.insert(time);history.insert(time,at:history.firstIndex(where:{$0>time}) ?? history.endIndex)
        if history.count>capacity {
            let retired=history.removeFirst();seen.remove(retired);retiredThrough=retired
        }
        if time<latest {reordered += 1}
        latest=max(latest,time);rate.frames += 1
        // Delay gap accounting briefly so reordered callbacks do not manufacture
        // a long gap. An unusually late callback still counts as a unique update,
        // but cannot retrospectively change an already reported gap.
        if time>lastGapTime {
            pending.insert(time,at:pending.firstIndex(where:{$0>time}) ?? pending.endIndex)
            flushGaps(through:latest-reorderWindow)
            if pending.count>capacity {flushGaps(through:pending[0])}
        } else {lateGap += 1}
        return true
    }
    private mutating func flushGaps(through cutoff:Double) {
        while let time=pending.first,time<=cutoff {
            pending.removeFirst()
            if lastGapTime>0 {
                let gap=(time-lastGapTime)*1000
                maxGapMS=max(maxGapMS,gap)
                if gap>25 {longGaps += 1}
            }
            lastGapTime=time
        }
    }
    mutating func take(now:Double=ProcessInfo.processInfo.systemUptime)->Sample {
        flushGaps(through:now-reorderWindow)
        let unique=rate.frames, measured=rate.take(now:now)
        let result=Sample(uniquePerSecond:measured.fps,positivePerSecond:positiveRate.take(now:now).fps,unique:unique,maxGapMS:maxGapMS,longGaps:longGaps,repeated:repeated,zero:zero,invalid:invalid,reordered:reordered,stale:stale,lateGap:lateGap)
        maxGapMS=0;longGaps=0;repeated=0;zero=0;invalid=0;reordered=0;stale=0;lateGap=0
        return result
    }
}

final class ViewerStatistics {
    private let lock = NSLock()
    private var rate = RateWindow()
    private var width = 0, height = 0, count = 0
    private var queue = 0.0, unpack = 0.0, upload = 0.0, drawable = 0.0, gpu = 0.0, total = 0.0
    private var assembly = 0.0, assembled = 0
    private var submission=0.0, callback=0.0, presentCall=0.0
    private var maxAssembly=0.0, maxSubmission=0.0, maxCallback=0.0, maxPresentCall=0.0, maxTotal=0.0
    private var presentations = PresentationCounter()
    private var drawableWidth = 0, drawableHeight = 0
    private var actualPresent=0.0,maxActualPresent=0.0,actualPresents=0
    func actualPresentCall(_ ms: Double) {
        lock.lock();defer {lock.unlock()}
        actualPresent += ms;maxActualPresent=max(maxActualPresent,ms);actualPresents += 1
    }
    func presented(width: Int, height: Int, time: Double) {
        lock.lock(); defer { lock.unlock() }
        guard presentations.record(time) else {return}
        drawableWidth = width; drawableHeight = height
    }
    func receivedBody(in milliseconds: Double) {
        lock.lock(); defer { lock.unlock() }; assembly += milliseconds; assembled += 1;maxAssembly=max(maxAssembly,milliseconds)
    }
    func received(_ bytes: Int) {
        lock.lock(); defer { lock.unlock() }; rate.bytes += bytes
    }
    func completed(_ t: RenderTiming) {
        lock.lock(); defer { lock.unlock() }
        rate.frames += 1; count += 1; width = t.width; height = t.height
        queue += t.queueMS; unpack += t.unpackMS; upload += t.uploadMS
        drawable += t.drawableMS; gpu += t.gpuMS; total += t.totalMS
        submission += t.submissionMS;callback += t.callbackMS;presentCall += t.presentMS
        maxSubmission=max(maxSubmission,t.submissionMS);maxCallback=max(maxCallback,t.callbackMS);maxPresentCall=max(maxPresentCall,t.presentMS);maxTotal=max(maxTotal,t.totalMS)
    }
    func report() -> String {
        lock.lock(); defer { lock.unlock() }
        let rates = rate.take(), presented = presentations.take(), n = Double(max(1,count))
        let headline = String(format:"%d × %d · %.1f rendered updates/s · %.1f Mbps",width,height,rates.fps,rates.mbps)
        let timing = count == 0 ? "Idle — no completed frames in this interval." : String(format:"Average ms: queue %.1f · unpack %.1f · upload setup %.1f\nDrawable wait %.1f · GPU %.1f · receiver total %.1f",queue/n,unpack/n,upload/n,drawable/n,gpu/n,total/n)
        let transport = assembled == 0 ? "" : String(format:"\nNetwork body assembly %.1f ms · max %.1f ms (before render timings)",assembly/Double(assembled),maxAssembly)
        let stalls = count == 0 ? "" : String(format:"\nGPU start delay %.2f ms · max %.2f ms · completion callback %.2f ms · max %.2f ms\nPresentation call %.2f ms · max %.2f ms · max receiver total %.2f ms",submission/n,maxSubmission,callback/n,maxCallback,presentCall/n,maxPresentCall,maxTotal)
        count = 0; queue = 0; unpack = 0; upload = 0; drawable = 0; gpu = 0; total = 0; assembly = 0; assembled = 0
        submission=0;callback=0;presentCall=0;maxAssembly=0;maxSubmission=0;maxCallback=0;maxPresentCall=0;maxTotal=0
        let presentation = String(format:"\nPresentation timing (API): %.1f unique timestamps/s · %.1f positive callbacks/s · drawable %d × %d\nAPI timestamp gap max %.1f ms · gaps >25 ms %d",presented.uniquePerSecond,presented.positivePerSecond,drawableWidth,drawableHeight,presented.maxGapMS,presented.longGaps)
        let callbacks = "\nPresentation callbacks: repeated timestamp \(presented.repeated) · zero \(presented.zero) · reordered \(presented.reordered) · stale \(presented.stale) · invalid \(presented.invalid) · late gap \(presented.lateGap)"
        let actual = actualPresents == 0 ? "" : String(format:"\nDeferred drawable present %.3f ms · max %.3f ms (%d calls)",actualPresent/Double(actualPresents),maxActualPresent,actualPresents)
        actualPresent=0;maxActualPresent=0;actualPresents=0
        return headline + "\n" + timing + transport + stalls + presentation + callbacks + actual + "\nAPI timing is not physical display FPS; driver timestamps can repeat or be zero for displayed frames."
    }
}
