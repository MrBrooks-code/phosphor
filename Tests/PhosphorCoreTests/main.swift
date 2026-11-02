import Foundation
import AudioIngress
import PhosphorCore

// Fail the process on a contract violation. This runner needs no Xcode test framework.
nonisolated(unsafe) private var failures = 0
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a != b { print("FAIL \(file):\(line): \(a) != \(b)"); failures += 1 }
}
func expectEqual(_ a: Float, _ b: Float, accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    if abs(a-b) > accuracy { print("FAIL \(file):\(line): difference exceeds \(accuracy)"); failures += 1 }
}
func expectGreaterThan<T: Comparable>(_ a: T, _ b: T) { if !(a > b) { print("FAIL \(a) is not greater than \(b)"); failures += 1 } }
func expectLessThan<T: Comparable>(_ a: T, _ b: T) { if !(a < b) { print("FAIL \(a) is not less than \(b)"); failures += 1 } }
func expectTrue(_ value: Bool) { if !value { print("FAIL expected true"); failures += 1 } }
func expectNil<T>(_ value: T?) { if value != nil { print("FAIL expected nil"); failures += 1 } }
func expectThrowsError<T>(_ operation: @autoclosure () throws -> T) {
    do { _ = try operation(); print("FAIL expected error"); failures += 1 } catch {}
}
final class PhosphorCoreTests {
    func testQueueWrapAndOverflowKeepOrderAndReportGap() {
        let queue = ingress_create()!; defer { ingress_destroy(queue) }
        for i in 0..<65540 { ingress_push(queue, Float(i), -Float(i), UInt64(i*10)) }
        expectEqual(ingress_dropped(queue),4)
        var frames = [StereoFrame](repeating: StereoFrame(),count: 65536)
        expectEqual(ingress_read(queue,&frames,65536),65536)
        expectEqual(frames.last!.left,65535); expectEqual(frames.last!.right,-65535)
        expectEqual(frames.last!.hostTime,655350)
        ingress_push(queue, 8, -8, 999)
        expectEqual(ingress_read(queue,&frames,1),1); expectEqual(frames[0].sequence,65540)
    }
    func testHistoryWrapPreservesStereoAndTimestamps() {
        let history = SampleHistory(capacity: 4)
        for i in 0..<7 { history.append(StereoFrame(left: Float(i),right: -Float(i),hostTime: UInt64(i*50),sequence: UInt64(i))) }
        expectEqual(history.count,4)
        expectEqual((0..<4).map { history.left[history.indexFromEnd($0)] },[6,5,4,3])
        expectEqual(history.right[history.indexFromEnd(1)],-5)
        expectEqual(history.times[history.indexFromEnd(0)],300)
        history.append(StereoFrame(left: 9,right: -9,hostTime: 500,sequence: 9))
        expectEqual(history.count,1); expectEqual(history.discontinuities,1)
    }
    func tone(_ frequency: Double, antiPhase: Bool = false) -> AudioAnalyzer {
        let analyzer = AudioAnalyzer()
        let frames = (0..<4096).map { i in
            let sample = Float(sin(Double(i)*2*Double.pi*frequency/48000))*0.4
            return StereoFrame(left: sample,right: antiPhase ? -sample : sample,hostTime: UInt64(i),sequence: UInt64(i))
        }
        frames.withUnsafeBufferPointer { analyzer.append($0) }
        return analyzer
    }
    func testStereoAntiPhaseDoesNotCancelSpectrum() {
        let analyzer = tone(93.75, antiPhase: true)
        let feature = analyzer.analyse(sampleRate: 48000,elapsed: 0.05,fresh: true)
        expectGreaterThan(feature.bass,0.5); expectLessThan(feature.mid,0.01)
        expectGreaterThan(feature.rms,0.2)
        expectEqual(feature.left[200],-feature.right[200],accuracy: 0.00001)
    }
    func testHighFrequencyAndSilenceRelease() {
        let analyzer = tone(6000)
        let live = analyzer.analyse(sampleRate: 48000,elapsed: 0.05,fresh: true)
        expectGreaterThan(live.high,0.5); expectLessThan(live.bass,0.01)
        var quiet = live
        for _ in 0..<30 { quiet = analyzer.analyse(sampleRate: 48000,elapsed: 0.05,fresh: false) }
        expectLessThan(quiet.high,0.002); expectLessThan(quiet.rms,0.002)
        expectTrue(quiet.left.allSatisfy {$0 == 0})
    }
    func testIndependentMirrorAndCoordinatedSettings() {
        var a = OutputState(name: "A",scene: .scope,palette: .mint)
        var b = OutputState(name: "B",scene: .tunnel,palette: .ember)
        a.settings.intensity = 1.5
        expectEqual(b.resolved(leader: a).scene,.tunnel)
        expectEqual(b.resolved(leader: a).palette,.ember)
        b.role = .mirrored; expectEqual(b.resolved(leader: a),a.settings)
        b.role = .coordinated
        expectEqual(b.resolved(leader: a).scene,.tunnel)
        expectEqual(b.resolved(leader: a).palette,.mint)
        expectEqual(b.resolved(leader: a).intensity,1.5)
        b.screenID = 456; b.quality = .native
        expectEqual(b.settings.scene,.tunnel); expectNil(a.screenID)
    }
    func testVersionedSaveAndInvalidData() throws {
        let outputs = [OutputState(name: "A"),OutputState(name: "B",scene: .bloom)]
        let data = try JSONEncoder().encode(SavedDesk(outputs: outputs))
        expectEqual(try SavedDesk.decode(data).outputs,outputs)
        let future = String(decoding: data,as: UTF8.self).replacingOccurrences(of: "\"version\":1",with: "\"version\":2")
        expectThrowsError(try SavedDesk.decode(Data(future.utf8)))
        var invalid = outputs[0]; invalid.settings.persistence = 2
        expectThrowsError(try SavedDesk.decode(JSONEncoder().encode(SavedDesk(outputs: [invalid]))))
        expectThrowsError(try SavedDesk.decode(JSONEncoder().encode(SavedDesk(outputs: [outputs[0], outputs[0]]))))
    }
    func testResolutionCaps() {
        expectEqual(Quality.balanced.scale(width: 3840,height: 2160),0.5)
        expectEqual(Quality.native.scale(width: 3840,height: 2160),1)
    }
}

let checks = PhosphorCoreTests()
checks.testQueueWrapAndOverflowKeepOrderAndReportGap()
checks.testHistoryWrapPreservesStereoAndTimestamps()
checks.testStereoAntiPhaseDoesNotCancelSpectrum()
checks.testHighFrequencyAndSilenceRelease()
checks.testIndependentMirrorAndCoordinatedSettings()
try checks.testVersionedSaveAndInvalidData()
checks.testResolutionCaps()
print("7 core checks completed; \(failures) failures")
exit(failures == 0 ? 0 : 1)
