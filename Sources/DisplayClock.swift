import Foundation
import CoreVideo
import CoreGraphics
import QuartzCore

// Opt-in timing only. CVDisplayLink is available on the Big Sur receiver; this
// probe does not drive rendering or change the layer's presentation policy.
final class DisplayRefreshClock {
    struct Sample {
        // CVDisplayLink's predicted output refresh in CACurrentMediaTime's clock.
        // Consumers must check observedAt and advance a stale prediction by period.
        let nextRefresh: Double
        let period: Double
        let observedAt: Double
    }

    // The display link retains its output block, which retains this state rather
    // than the owner. A callback already in flight remains safe during stop or
    // deinit, without an unretained context pointer or an owner/link retain cycle.
    private final class CallbackState {
        let traceID: String
        let displayID: CGDirectDisplayID
        let nominal: CVTime
        let frequency: Double
        private let lock = NSLock()
        private var enabled = true
        private var latest: Sample?

        init(traceID: String, displayID: CGDirectDisplayID, nominal: CVTime) {
            self.traceID = traceID
            self.displayID = displayID
            self.nominal = nominal
            frequency = CVGetHostClockFrequency()
        }

        func disable() {
            lock.lock(); enabled = false; latest = nil; lock.unlock()
        }

        func sample() -> Sample? {
            lock.lock(); defer { lock.unlock() }
            return enabled ? latest : nil
        }

        func receive(input: CVTimeStamp, output: CVTimeStamp, flagsIn: CVOptionFlags) {
            let before = CACurrentMediaTime()
            let currentHost = CVGetCurrentHostTime()
            let now = (before + CACurrentMediaTime()) * 0.5
            let hostFlag = CVTimeStampFlags.hostTimeValid.rawValue
            let periodFlag = CVTimeStampFlags.videoRefreshPeriodValid.rawValue
            let rateFlag = CVTimeStampFlags.rateScalarValid.rawValue
            func translated(_ stamp: CVTimeStamp) -> Double? {
                guard frequency.isFinite, frequency > 0,
                      stamp.flags & hostFlag != 0, stamp.hostTime > 0 else { return nil }
                return now + (Double(stamp.hostTime) - Double(currentHost)) / frequency
            }
            let inputTime = translated(input), outputTime = translated(output)
            let nominalValid = nominal.flags & CVTimeFlags.isIndefinite.rawValue == 0 && nominal.timeScale > 0 && nominal.timeValue > 0
            let nominalPeriod = nominalValid ? Double(nominal.timeValue) / Double(nominal.timeScale) : 0
            let videoPeriodValid = output.flags & periodFlag != 0 && output.videoTimeScale > 0 && output.videoRefreshPeriod > 0
            let videoPeriod = videoPeriodValid ? Double(output.videoRefreshPeriod) / Double(output.videoTimeScale) : nominalPeriod
            let scalarValid = output.flags & rateFlag != 0 && output.rateScalar.isFinite && output.rateScalar > 0
            let period = videoPeriod / (scalarValid ? output.rateScalar : 1)
            let usablePeriod = period.isFinite && period > 0 && period <= 1

            lock.lock()
            guard enabled else { lock.unlock(); return }
            if let refresh = outputTime, usablePeriod {
                latest = Sample(nextRefresh:refresh, period:period, observedAt:now)
            }
            lock.unlock()

            FrameTrace.shared.event("display_refresh", fields:[
                "view":traceID, "display":displayID, "now":now,
                "input_host":inputTime ?? -1, "output_host":outputTime ?? -1,
                "input_host_valid":inputTime != nil, "output_host_valid":outputTime != nil,
                "input_host_ticks":input.hostTime, "output_host_ticks":output.hostTime,
                "host_ticks":currentHost, "host_frequency":frequency,
                "input_flags":input.flags, "output_flags":output.flags, "callback_flags":flagsIn,
                "input_video_time":input.videoTime, "input_video_scale":input.videoTimeScale,
                "output_video_time":output.videoTime, "output_video_scale":output.videoTimeScale,
                "output_video_period":output.videoRefreshPeriod,
                "video_period_valid":videoPeriodValid, "rate_scalar":output.rateScalar,
                "rate_scalar_valid":scalarValid, "nominal_value":nominal.timeValue,
                "nominal_scale":nominal.timeScale, "nominal_flags":nominal.flags,
                "nominal_period":nominalPeriod, "period":usablePeriod ? period : -1
            ])
        }
    }

    private let traceID: String
    private let lifecycleLock = NSLock()
    private var link: CVDisplayLink?
    private var state: CallbackState?

    init(traceID: String) { self.traceID = traceID }

    func start(displayID: CGDirectDisplayID) {
        guard LaunchOptions.has("--trace-display-clock") || LaunchOptions.has("--refresh-plan") else { return }
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        if state?.displayID == displayID, link != nil { return }
        stopLocked()
        var created: CVDisplayLink?
        let createResult = CVDisplayLinkCreateWithCGDisplay(displayID, &created)
        guard createResult == kCVReturnSuccess, let created = created else {
            DiagnosticLog.shared.record("display-clock", "Could not create refresh probe for display \(displayID): \(createResult)")
            return
        }
        let callbackState = CallbackState(traceID:traceID, displayID:displayID,
            nominal:CVDisplayLinkGetNominalOutputVideoRefreshPeriod(created))
        let callbackResult = CVDisplayLinkSetOutputHandler(created) { _, input, output, flagsIn, _ in
            callbackState.receive(input:input.pointee, output:output.pointee, flagsIn:flagsIn)
            return kCVReturnSuccess
        }
        guard callbackResult == kCVReturnSuccess else {
            callbackState.disable()
            DiagnosticLog.shared.record("display-clock", "Could not set refresh probe callback: \(callbackResult)")
            return
        }
        let startResult = CVDisplayLinkStart(created)
        guard startResult == kCVReturnSuccess else {
            callbackState.disable()
            DiagnosticLog.shared.record("display-clock", "Could not start refresh probe: \(startResult)")
            return
        }
        state = callbackState; link = created
        FrameTrace.shared.event("display_clock_start", fields:["view":traceID, "display":displayID])
    }

    func sample() -> Sample? {
        lifecycleLock.lock(); let current = state; lifecycleLock.unlock()
        return current?.sample()
    }

    func stop() {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        state?.disable()
        if let link = link {
            CVDisplayLinkStop(link)
            FrameTrace.shared.event("display_clock_stop", fields:["view":traceID])
        }
        link = nil; state = nil
    }

    deinit { stop() }
}

// Confined to the render queue. This opt-in experiment assigns one predicted
// physical refresh to each frame without delaying a frame by an unbounded queue.
struct RefreshSlotScheduler {
    private var previous: Double?

    mutating func reset() { previous = nil }

    mutating func target(now: Double, sample: DisplayRefreshClock.Sample) -> Double? {
        let period = sample.period, age = now - sample.observedAt
        guard now.isFinite, sample.nextRefresh.isFinite, sample.observedAt.isFinite,
              period.isFinite, (1.0 / 240.0...1.0 / 20.0).contains(period),
              age >= 0, age <= 0.100 else { reset(); return nil }

        // Present just before the predicted refresh, allowing at least 12 ms
        // for upload/GPU submission. Advance only by whole physical periods.
        var target = sample.nextRefresh - 0.002
        let earliest = now + 0.012
        if target < earliest { target += ceil((earliest - target) / period) * period }
        if let previous = previous, target <= previous + period * 0.5 {
            // CVDisplayLink can make small phase corrections. A strict
            // previous+period threshold would accidentally skip a whole slot.
            target += (floor((previous + period * 0.5 - target) / period) + 1) * period
        }
        let lead = target - now
        guard target.isFinite, lead >= 0.012 - 1e-9, lead <= 0.050 else { reset(); return nil }
        previous = target
        return target
    }
}

// An independent experiment: align normal immediate presentation's submission
// to the display clock rather than assigning a future drawable presentation.
struct RefreshSubmissionScheduler {
    private var previous: Double?

    mutating func reset() { previous = nil }

    mutating func target(now: Double, sample: DisplayRefreshClock.Sample) -> Double? {
        let period = sample.period, age = now - sample.observedAt
        guard now.isFinite, sample.nextRefresh.isFinite, sample.observedAt.isFinite,
              period.isFinite, (1.0 / 240.0...1.0 / 20.0).contains(period),
              age >= 0, age <= 0.100 else { reset(); return nil }

        // Wake the render queue 12 ms before a predicted physical refresh.
        // Never create an unbounded wait or reuse a previously assigned slot.
        var target = sample.nextRefresh - 0.012
        let earliest = now + 0.0005
        if target < earliest { target += ceil((earliest - target) / period) * period }
        if let previous = previous, target <= previous + period * 0.5 {
            target += (floor((previous + period * 0.5 - target) / period) + 1) * period
        }
        let wait = target - now
        guard target.isFinite, wait >= 0.0005 - 1e-9, wait <= 0.035 else { reset(); return nil }
        previous = target
        return target
    }
}
