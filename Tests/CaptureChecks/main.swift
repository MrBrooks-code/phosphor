import Foundation
import CoreAudio
import AudioIngress
import PhosphorCapture

// Inject HAL failures to check ownership without creating a native device.
final class Fixture {
    var calls: [String] = []
    var failure: String?
    var invalidInput = false
    let error: OSStatus = 268451843
    func result(_ name: String) -> OSStatus {
        calls.append(name); return failure == name ? error : noErr
    }
    func hardware() -> CaptureHardware {
        var value = CaptureHardware()
        value.createTap = { _, id in let s = self.result("tap"); if s == noErr { id = 10 }; return s }
        value.property = { id, _, size, data in
            let s = self.result(id == 10 ? "format" : "inputFormat")
            data.assumingMemoryBound(to: AudioStreamBasicDescription.self).pointee = AudioStreamBasicDescription(
                mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat,
                mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: self.invalidInput && id == 20 ? 1 : 2, mBitsPerChannel: 32, mReserved: 0)
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            return s
        }
        value.createAggregate = { composition, id in
            let description = composition as NSDictionary
            precondition(description[kAudioAggregateDeviceTapAutoStartKey] as? Bool == false)
            precondition(description[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
            precondition(description[kAudioAggregateDeviceSubDeviceListKey] == nil)
            let s = self.result("aggregate"); if s == noErr { id = 20 }; return s
        }
        value.createProc = { _, _, proc in let s = self.result("proc"); if s == noErr { proc = ingress_callback }; return s }
        value.start = { _, _ in self.result("start") }
        value.stop = { _, _ in self.result("stop") }
        value.destroyProc = { _, _ in self.result("destroyProc") }
        value.destroyAggregate = { _ in self.result("destroyAggregate") }
        value.destroyTap = { _ in self.result("destroyTap") }
        return value
    }
}
var count = 0
func expect(_ condition: @autoclosure () -> Bool, _ detail: String) {
    guard condition() else { fatalError(detail) }; count += 1
}
for (failure, suffix) in [
    ("tap", [String]()), ("format", ["destroyTap"]),
    ("aggregate", ["destroyTap"]), ("inputFormat", ["destroyAggregate", "destroyTap"]), ("proc", ["destroyAggregate", "destroyTap"]),
    ("start", ["stop", "destroyProc", "destroyAggregate", "destroyTap"])
] {
    let fixture = Fixture(); fixture.failure = failure
    let capture = AudioCapture(hardware: fixture.hardware())
    do { try capture.start(musicOnly: true); fatalError("Expected \(failure) failure") }
    catch let error as CaptureFailure { expect(error.status == fixture.error, "Preserve native error") }
    expect(fixture.calls.suffix(suffix.count) == suffix[...], "Release only owned resources after \(failure): \(fixture.calls)")
    let calls = fixture.calls
    expect(capture.stop(), "Cleanup is complete")
    expect(fixture.calls == calls, "Repeated stop must be idle")
}
let fixture = Fixture()
var capture: AudioCapture? = AudioCapture(hardware: fixture.hardware())
try capture!.start(musicOnly: true)
fixture.failure = "destroyProc"
expect(!capture!.stop(), "Report incomplete cleanup")
expect(!fixture.calls.contains("destroyAggregate"), "Retain aggregate and tap while callback is owned")
do { try capture!.start(musicOnly: true); fatalError("Do not overlap sessions") } catch {}
expect(fixture.calls.filter { $0 == "tap" }.count == 1, "Do not create another tap while cleanup fails")
fixture.failure = nil
expect(capture!.stop(), "Cleanup can finish after native boundary recovers")
try capture!.start(musicOnly: true)
capture = nil
expect(fixture.calls.suffix(4) == ["stop", "destroyProc", "destroyAggregate", "destroyTap"], "Deinit releases a live session in order")
for failure in ["stop", "destroyAggregate", "destroyTap"] {
    let fixture = Fixture()
    let capture = AudioCapture(hardware: fixture.hardware())
    try capture.start(musicOnly: true)
    fixture.failure = failure
    expect(!capture.stop(), "Report \(failure) failure")
    expect(capture.cleanupFailure != nil, "Retain cleanup diagnostics")
    if failure == "stop" { expect(!fixture.calls.contains("destroyProc"), "Keep a potentially live callback") }
    if failure == "destroyAggregate" { expect(!fixture.calls.contains("destroyTap"), "Keep the aggregate's tap") }
    fixture.failure = nil
    expect(capture.stop(), "Resume cleanup in ownership order")
    expect(capture.cleanupFailure == nil, "Clear recovered error")
}
let invalid = Fixture(); invalid.invalidInput = true
let invalidCapture = AudioCapture(hardware: invalid.hardware())
do { try invalidCapture.start(musicOnly: true); fatalError("Reject mono input") } catch {}
expect(!invalid.calls.contains("proc"), "Validate actual aggregate stereo before callback registration")
expect(invalid.calls.suffix(2) == ["destroyAggregate", "destroyTap"], "Clean up after input format rejection")
let timeout = CaptureFailure(operation: "Start capture", status: 268451843).localizedDescription
expect(timeout.contains("timed out") && !timeout.contains("retry"), "Do not misdiagnose a server timeout as denied permission")
print("\(count) capture lifecycle assertions completed; 0 failures")
