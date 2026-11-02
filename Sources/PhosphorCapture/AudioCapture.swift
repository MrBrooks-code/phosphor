import Foundation
import CoreAudio
import AudioIngress
import PhosphorCore

package struct CaptureFailure: LocalizedError {
    package let operation: String
    package let status: OSStatus?
    package init(operation: String, status: OSStatus?) { self.operation = operation; self.status = status }
    package var errorDescription: String? {
        guard let status else { return operation }
        if status == 268451843 { return "\(operation): Core Audio server reply timed out (\(status)). This does not establish a permission denial." }
        return "\(operation): Core Audio error \(status). System Audio Recording permission, source state and content access are unverified."
    }
}

// Keep native calls replaceable so failure paths can run without audio or permission changes.
package struct CaptureHardware {
    package init() {}
    package var createTap: (CATapDescription, inout AudioObjectID) -> OSStatus = { AudioHardwareCreateProcessTap($0, &$1) }
    package var property: (AudioObjectID, inout AudioObjectPropertyAddress, inout UInt32, UnsafeMutableRawPointer) -> OSStatus = {
        AudioObjectGetPropertyData($0, &$1, 0, nil, &$2, $3)
    }
    package var createAggregate: (CFDictionary, inout AudioObjectID) -> OSStatus = { AudioHardwareCreateAggregateDevice($0, &$1) }
    package var createProc: (AudioObjectID, UnsafeMutableRawPointer, inout AudioDeviceIOProcID?) -> OSStatus = {
        AudioDeviceCreateIOProcID($0, ingress_callback, $1, &$2)
    }
    package var start: (AudioObjectID, AudioDeviceIOProcID?) -> OSStatus = AudioDeviceStart
    package var stop: (AudioObjectID, AudioDeviceIOProcID?) -> OSStatus = AudioDeviceStop
    package var destroyProc: (AudioObjectID, AudioDeviceIOProcID) -> OSStatus = AudioDeviceDestroyIOProcID
    package var destroyAggregate: (AudioObjectID) -> OSStatus = AudioHardwareDestroyAggregateDevice
    package var destroyTap: (AudioObjectID) -> OSStatus = AudioHardwareDestroyProcessTap
}

// Own one private capture session. All methods run on the analysis worker.
package final class AudioCapture {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?
    private var started = false
    private let hardware: CaptureHardware
    private let report: (String) -> Void
    package private(set) var cleanupFailure: String?
    let queue = ingress_create()!
    private(set) var sampleRate: Double = 48000
    package init(hardware: CaptureHardware = CaptureHardware(), report: @escaping (String) -> Void = { _ in }) {
        self.hardware = hardware; self.report = report
    }
    deinit {
        // Retain the callback context if HAL could not release its IOProc.
        if stop() { ingress_destroy(queue) }
    }
    private func check(_ operation: String, _ call: () -> OSStatus) throws {
        report(operation)
        let begin = ProcessInfo.processInfo.systemUptime
        let status = call()
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            print("CAPTURE operation=\(operation) duration_ms=\(String(format: "%.2f", (ProcessInfo.processInfo.systemUptime-begin)*1000)) status=\(status)")
            fflush(stdout)
        }
        if status != noErr { throw CaptureFailure(operation: operation, status: status) }
    }
    package func start(musicOnly: Bool) throws {
        guard stop() else { throw CaptureFailure(operation: "Previous capture teardown is incomplete; no new tap was created", status: nil) }
        do {
            let description: CATapDescription
            if musicOnly {
                guard #available(macOS 26, *) else { throw CaptureFailure(operation: "Music-only mode needs macOS 26", status: nil) }
                description = CATapDescription(stereoMixdownOfProcesses: [])
                description.bundleIDs = ["com.apple.Music"]
                description.isProcessRestoreEnabled = true
            } else { description = CATapDescription(stereoGlobalTapButExcludeProcesses: []) }
            description.name = "Phosphor stereo analysis"
            description.isPrivate = true; description.muteBehavior = .unmuted
            try check("Create process tap") { hardware.createTap(description, &tap) }
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var format = AudioStreamBasicDescription(); var size = UInt32(MemoryLayout.size(ofValue: format))
            try check("Read tap format") { hardware.property(tap, &address, &size, &format) }
            try validate(format)
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Phosphor private capture",
                kAudioAggregateDeviceUIDKey: "com.mrbrooks.phosphor.capture.\(UUID())",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try check("Create private aggregate") { hardware.createAggregate(composition as CFDictionary, &aggregate) }
            // Read the aggregate's published input format before registering stream usage.
            address.mSelector = kAudioDevicePropertyStreamFormat; address.mScope = kAudioObjectPropertyScopeInput
            var input = AudioStreamBasicDescription(); size = UInt32(MemoryLayout.size(ofValue: input))
            try check("Read aggregate input format") { hardware.property(aggregate, &address, &size, &input) }
            try validate(input)
            sampleRate = input.mSampleRate; ingress_set_rate(queue, sampleRate)
            try check("Create capture callback") { hardware.createProc(aggregate, UnsafeMutableRawPointer(queue), &proc) }
            guard proc != nil else { throw CaptureFailure(operation: "Core Audio returned no capture callback", status: nil) }
            started = true
            try check("Start capture") { hardware.start(aggregate, proc) }
        } catch {
            _ = stop(); throw error
        }
    }
    private func validate(_ format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 2,
              format.mSampleRate.isFinite, format.mSampleRate > 0 else {
            throw CaptureFailure(operation: "Unsupported capture format (requires Float32 stereo and a valid sample rate)", status: nil)
        }
    }
    @discardableResult package func stop() -> Bool {
        do {
            if let proc {
                if started { try check("Stop capture") { hardware.stop(aggregate, proc) }; started = false }
                try check("Destroy capture callback") { hardware.destroyProc(aggregate, proc) }
                self.proc = nil
            }
            if aggregate != 0 {
                try check("Destroy private aggregate") { hardware.destroyAggregate(aggregate) }
                aggregate = 0
            }
            if tap != 0 { try check("Destroy process tap") { hardware.destroyTap(tap) }; tap = 0 }
            cleanupFailure = nil
            return true
        } catch {
            cleanupFailure = "Capture cleanup incomplete · \(error.localizedDescription)"
            report(cleanupFailure!)
            return false
        }
    }
}

// Publish immutable feature snapshots. Only the analysis worker reads the capture queue.
public final class AudioEngine: @unchecked Sendable {
    private let hardware: CaptureHardware
    private lazy var capture = AudioCapture(hardware: hardware) { [weak self] stage in
        self?.lock.lock(); self?.message = stage + " · waiting for Core Audio"; self?.lock.unlock()
    }
    public init() { hardware = CaptureHardware() }
    package init(hardware: CaptureHardware) { self.hardware = hardware }
    private let worker = DispatchQueue(label: "Phosphor.analysis", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var current = AudioFeatures()
    private var message = "Capture stopped · no audio source"
    private var rate: Double = 48000
    private var drops: UInt64 = 0
    public func snapshot() -> (AudioFeatures, String, Double, UInt64) {
        lock.lock(); defer { lock.unlock() }; return (current, message, rate, drops)
    }
    public func start(musicOnly: Bool, completion: @escaping (String?) -> Void) {
        worker.async { [self] in
            if let error = stopWorker() {
                DispatchQueue.main.async { completion(error) }; return
            }
            let begin = ProcessInfo.processInfo.systemUptime
            lock.lock(); message = "Starting capture · waiting for Core Audio"; lock.unlock()
            do {
                try capture.start(musicOnly: musicOnly)
                let analyzer = AudioAnalyzer()
                let frames = UnsafeMutablePointer<StereoFrame>.allocate(capacity: 8192)
                let timer = DispatchSource.makeTimerSource(queue: worker)
                var last = ProcessInfo.processInfo.systemUptime
                var lastData = last
                var sawFrames = false
                var sawSignal = false
                let diagnostics = ProcessInfo.processInfo.arguments.contains("--diagnostics")
                if diagnostics {
                    print("CAPTURE setup_ms=\(String(format: "%.2f", (last-begin)*1000)) sample_rate=\(capture.sampleRate)")
                    fflush(stdout)
                }
                timer.schedule(deadline: .now(), repeating: .milliseconds(8))
                timer.setEventHandler { [self] in
                    let now = ProcessInfo.processInfo.systemUptime
                    let n = ingress_read(capture.queue, frames, 8192)
                    if n > 0 { analyzer.append(UnsafeBufferPointer(start: frames, count: Int(n))); lastData = now }
                    let features = analyzer.analyse(sampleRate: capture.sampleRate, elapsed: now-last, fresh: now-lastData < 0.15)
                    if diagnostics {
                        if n > 0 && !sawFrames { print("CAPTURE first_callback_ms=\((now-begin)*1000)"); sawFrames = true }
                        if features.peak > 0.00001 && !sawSignal { print("CAPTURE first_signal_ms=\((now-begin)*1000)"); sawSignal = true }
                    }
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
    public func stop(completion: @escaping (String?) -> Void = { _ in }) {
        worker.async { [self] in
            let error = stopWorker()
            DispatchQueue.main.async { completion(error) }
        }
    }
    private func stopWorker() -> String? {
        timer?.cancel(); timer = nil
        lock.lock(); current = AudioFeatures(); lock.unlock()
        guard capture.stop() else {
            let failure = capture.cleanupFailure ?? "Capture cleanup incomplete"
            lock.lock(); message = failure; lock.unlock()
            return failure
        }
        var discard = [StereoFrame](repeating: StereoFrame(), count: 8192)
        while ingress_read(capture.queue, &discard, 8192) > 0 {}
        lock.lock(); current = AudioFeatures(); message = "Capture stopped · no audio source"; lock.unlock()
        return nil
    }
}
