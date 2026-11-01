import Foundation
import CoreAudio
import AudioIngress
import PhosphorCore

struct CaptureFailure: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "\(operation): Core Audio error \(status). Check System Settings → Privacy & Security → Screen & System Audio Recording, then retry capture." }
}

// Own the private tap and aggregate. Never change the system output or mute playback.
final class AudioCapture {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?
    let queue = ingress_create()!
    private(set) var sampleRate: Double = 48000
    deinit { stop(); ingress_destroy(queue) }
    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw CaptureFailure(operation: operation, status: status) }
    }
    func start(musicOnly: Bool) throws {
        stop()
        do {
            let description: CATapDescription
            if musicOnly {
                guard #available(macOS 26, *) else { throw CaptureFailure(operation: "Music-only mode needs macOS 26", status: -1) }
                description = CATapDescription(stereoMixdownOfProcesses: [])
                description.bundleIDs = ["com.apple.Music"]
                description.isProcessRestoreEnabled = true
            } else { description = CATapDescription(stereoGlobalTapButExcludeProcesses: []) }
            description.name = "Phosphor stereo analysis"
            description.isPrivate = true; description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap), "Create process tap")
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var format = AudioStreamBasicDescription(); var size = UInt32(MemoryLayout.size(ofValue: format))
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Read tap format")
            guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 2 else {
                throw CaptureFailure(operation: "Unsupported tap format (requires Float32 stereo)", status: -1)
            }
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Phosphor private capture",
                kAudioAggregateDeviceUIDKey: "com.mrbrooks.phosphor.capture.\(UUID())",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "Create private aggregate")
            address.mSelector = kAudioDevicePropertyNominalSampleRate
            var rate: Double = format.mSampleRate; size = UInt32(MemoryLayout<Double>.size)
            try check(AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &rate), "Read capture sample rate")
            guard rate > 0 else { throw CaptureFailure(operation: "Invalid capture rate", status: -1) }
            sampleRate = rate; ingress_set_rate(queue, rate)
            try check(AudioDeviceCreateIOProcID(aggregate, ingress_callback, UnsafeMutableRawPointer(queue), &proc), "Create capture callback")
            try check(AudioDeviceStart(aggregate, proc), "Start capture")
        } catch { stop(); throw error }
    }
    func stop() {
        if aggregate != 0 {
            if let proc { AudioDeviceStop(aggregate, proc); AudioDeviceDestroyIOProcID(aggregate, proc) }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        proc = nil; aggregate = 0; tap = 0
    }
}

// Publish immutable feature snapshots. Only the analysis worker reads the capture queue.
final class AudioEngine: @unchecked Sendable {
    private let capture = AudioCapture()
    private let worker = DispatchQueue(label: "Phosphor.analysis", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var current = AudioFeatures()
    private var message = "Capture stopped · no audio source"
    private var rate: Double = 48000
    private var drops: UInt64 = 0
    func snapshot() -> (AudioFeatures, String, Double, UInt64) {
        lock.lock(); defer { lock.unlock() }; return (current, message, rate, drops)
    }
    func start(musicOnly: Bool, completion: @escaping (String?) -> Void) {
        worker.async { [self] in
            stopWorker()
            do {
                try capture.start(musicOnly: musicOnly)
                let analyzer = AudioAnalyzer()
                let frames = UnsafeMutablePointer<StereoFrame>.allocate(capacity: 8192)
                let timer = DispatchSource.makeTimerSource(queue: worker)
                var last = ProcessInfo.processInfo.systemUptime
                var lastData = last
                timer.schedule(deadline: .now(), repeating: .milliseconds(8))
                timer.setEventHandler { [self] in
                    let now = ProcessInfo.processInfo.systemUptime
                    let n = ingress_read(capture.queue, frames, 8192)
                    if n > 0 { analyzer.append(UnsafeBufferPointer(start: frames, count: Int(n))); lastData = now }
                    let features = analyzer.analyse(sampleRate: capture.sampleRate, elapsed: now-last, fresh: now-lastData < 0.15)
                    last = now
                    lock.lock()
                    current = features; rate = capture.sampleRate; drops = ingress_dropped(capture.queue)
                    message = features.peak > 0.00001 ? "Live samples · \(musicOnly ? "Apple Music only" : "system mix")" : "Tap active · silence / permission / content restriction unverified"
                    lock.unlock()
                }
                timer.setCancelHandler { frames.deallocate() }
                self.timer = timer; timer.resume()
                DispatchQueue.main.async { completion(nil) }
            } catch {
                lock.lock(); message = error.localizedDescription; lock.unlock()
                DispatchQueue.main.async { completion(error.localizedDescription) }
            }
        }
    }
    func stop() { worker.async { [self] in stopWorker() } }
    private func stopWorker() {
        timer?.cancel(); timer = nil; capture.stop()
        var discard = [StereoFrame](repeating: StereoFrame(), count: 8192)
        while ingress_read(capture.queue, &discard, 8192) > 0 {}
        lock.lock(); current = AudioFeatures(); message = "Capture stopped · no audio source"; lock.unlock()
    }
}
