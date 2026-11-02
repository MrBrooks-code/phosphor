import Foundation
import Accelerate
import AudioIngress

public struct AudioFeatures: Sendable {
    public var left = [Float](repeating: 0, count: 512)
    public var right = [Float](repeating: 0, count: 512)
    public var spectrum = [Float](repeating: 0, count: 64)
    public var rms: Float = 0
    public var peak: Float = 0
    public var bass: Float = 0
    public var mid: Float = 0
    public var high: Float = 0
    public var transient: Float = 0
    public var lastHostTime: UInt64 = 0
    public var totalFrames: UInt64 = 0
    public var discontinuities: UInt64 = 0
    public init() {}
}

// Keep ordered stereo history. Reset history if the capture queue loses frames.
public final class SampleHistory {
    public private(set) var left: [Float]
    public private(set) var right: [Float]
    public private(set) var times: [UInt64]
    public private(set) var count = 0
    public private(set) var cursor = 0
    public private(set) var discontinuities: UInt64 = 0
    private var previousSequence: UInt64?
    public init(capacity: Int = 96000) {
        precondition(capacity > 0)
        left = .init(repeating: 0, count: capacity); right = left
        times = .init(repeating: 0, count: capacity)
    }
    public func append(_ frame: StereoFrame) {
        if let previousSequence, frame.sequence != previousSequence &+ 1 {
            count = 0; discontinuities += 1
        }
        previousSequence = frame.sequence
        left[cursor] = frame.left; right[cursor] = frame.right; times[cursor] = frame.hostTime
        cursor = (cursor + 1) % left.count; count = min(count + 1, left.count)
    }
    public func reset() { count = 0; cursor = 0; previousSequence = nil }
    public func indexFromEnd(_ offset: Int) -> Int { (cursor - 1 - offset + left.count) % left.count }
}

// Analyse each stereo channel before combining spectral power.
public final class AudioAnalyzer {
    public let history = SampleHistory()
    private let size = 2048
    private let fft: FFTSetup
    private var window = [Float](repeating: 0, count: 2048)
    private var real = [Float](repeating: 0, count: 2048)
    private var imaginary = [Float](repeating: 0, count: 2048)
    private var power = [Float](repeating: 0, count: 1024)
    private var total: UInt64 = 0
    private var previousRMS: Float = 0
    private var previousMagnitude = [Float](repeating: 0, count: 1024)
    private var referenceRMS: Float = 0.08
    private var fluxAverage: Float = 0.04
    private var analysedTotal: UInt64 = 0
    private var analysedGaps: UInt64 = 0
    private var primed = false
    private var feature = AudioFeatures()
    public init() {
        fft = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, 2048, Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_destroy_fftsetup(fft) }
    public func append(_ frames: UnsafeBufferPointer<StereoFrame>) {
        for frame in frames { history.append(frame); total += 1 }
    }
    public func analyse(sampleRate: Double, elapsed: Double, fresh: Bool) -> AudioFeatures {
        let dt = Float(elapsed.isFinite ? min(max(elapsed, 0.001), 1) : 0.008)
        let valid = fresh && sampleRate.isFinite && sampleRate > 0
        if !valid || history.discontinuities != analysedGaps {
            previousMagnitude = .init(repeating: 0, count: 1024)
            referenceRMS = 0.08; fluxAverage = 0.04; previousRMS = 0; primed = false
            analysedGaps = history.discontinuities
            if !valid { history.reset() }
        }
        let newSamples = total != analysedTotal
        analysedTotal = total
        var square: Float = 0; var peak: Float = 0
        let n = min(history.count, size)
        for i in 0..<n {
            let j = history.indexFromEnd(i); let l = history.left[j]; let r = history.right[j]
            square += (l*l+r*r)*0.5; peak = max(peak, max(abs(l), abs(r)))
        }
        let rms: Float = valid && n > 0 ? sqrt(square / Float(n)) : 0
        func follow(_ old: Float, _ value: Float, release: Float = 0.22) -> Float {
            old + (value-old) * (1-exp(-dt / (value > old ? 0.018 : release)))
        }
        feature.rms = follow(feature.rms, rms); feature.peak = valid ? peak : 0
        // Gate before gain. Quiet noise must not train sensitivity or create hits.
        let gate = min(1, max(0, (rms-0.0008)/0.0022))
        if gate > 0.5 && newSamples {
            referenceRMS += (rms-referenceRMS) * (1-exp(-dt/(rms > referenceRMS ? 3 : 8)))
        }
        let gain = min(3, max(0.75, sqrt(0.16/max(referenceRMS,0.018))))
        let sensitivity = gate * gain
        power.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        if valid && n == size {
            for channel in 0..<2 {
                for i in 0..<size {
                    let j = history.indexFromEnd(size-1-i)
                    real[i] = (channel == 0 ? history.left[j] : history.right[j]) * window[i]
                    imaginary[i] = 0
                }
                real.withUnsafeMutableBufferPointer { rp in
                    imaginary.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        vDSP_fft_zip(fft, &split, 1, 11, FFTDirection(FFT_FORWARD))
                        for i in 0..<1024 { power[i] += (rp[i]*rp[i]+ip[i]*ip[i]) / Float(size*size) }
                    }
                }
            }
        }
        var bass: Float = 0; var mid: Float = 0; var high: Float = 0
        var flux: Float = 0; var magnitudeSum: Float = 0
        for i in 1..<1024 {
            let magnitude = sqrt(power[i])
            flux += max(0, magnitude-previousMagnitude[i]); magnitudeSum += magnitude
            if newSamples { previousMagnitude[i] = magnitude }
            let hz = Double(i)*sampleRate/Double(size)
            if hz < 180 { bass += power[i] } else if hz < 2400 { mid += power[i] } else { high += power[i] }
        }
        // Positive spectral change catches percussion under a sustained loud passage.
        // Prime a full window after gaps so old history cannot create a restart hit.
        let fluxRate = flux/max(magnitudeSum,0.005) * min(2,0.008/dt)
        let spectralRise = max(0,fluxRate-max(0.035,fluxAverage*1.4)) * 4
        if newSamples && gate > 0.5 { fluxAverage += (fluxRate-fluxAverage)*(1-exp(-dt/0.4)) }
        let levelRise = max(0,rms-previousRMS)/max(referenceRMS,0.025)*1.8
        let hit = primed && newSamples ? min(1,max(spectralRise,levelRise)*gate) : 0
        feature.transient += (hit-feature.transient) * (1-exp(-dt/(hit > feature.transient ? 0.006 : 0.09)))
        if newSamples { previousRMS = rms; primed = valid && n == size && gate > 0.5 }
        feature.bass = follow(feature.bass, min(1, sqrt(bass)*5*sensitivity), release: 0.18)
        feature.mid = follow(feature.mid, min(1, sqrt(mid)*5*sensitivity))
        feature.high = follow(feature.high, min(1, sqrt(high)*7*sensitivity), release: 0.13)
        for band in 0..<64 {
            let lo = max(1, Int(pow(1000, Double(band)/64)))
            let hi = min(1023, max(lo+1, Int(pow(1000, Double(band+1)/64))))
            var sum: Float = 0
            for i in lo..<hi { sum += power[i] }
            feature.spectrum[band] = follow(feature.spectrum[band], min(1, sqrt(sum)*7*sensitivity), release: 0.16)
        }
        for i in 0..<512 {
            let offset = (511-i)*3
            let j = history.indexFromEnd(min(offset, max(0,history.count-1)))
            feature.left[i] = valid && history.count > 0 ? history.left[j] : 0
            feature.right[i] = valid && history.count > 0 ? history.right[j] : 0
        }
        feature.lastHostTime = history.count > 0 ? history.times[history.indexFromEnd(0)] : 0
        feature.totalFrames = total; feature.discontinuities = history.discontinuities
        return feature
    }
}
