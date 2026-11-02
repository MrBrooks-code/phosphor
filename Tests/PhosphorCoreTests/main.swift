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
    func testSceneCompatibilityAndIndependentNewScenes() throws {
        expectEqual(Scene.allCases.count,8)
        expectEqual(Scene.scope.shaderID,0); expectEqual(Scene.bloom.shaderID,1); expectEqual(Scene.tunnel.shaderID,2)
        expectEqual(Set(Scene.allCases.map(\.shaderID)).count,8)
        let oldNames = ["Phosphor Scope", "Feedback Bloom", "Vector Tunnel"]
        for (index,name) in oldNames.enumerated() {
            let decoded = try JSONDecoder().decode(Scene.self,from: JSONEncoder().encode(name))
            expectEqual(decoded.shaderID,UInt32(index))
        }
        let scenes: [Scene] = [.outrun,.crystal,.galaxy,.rain,.plasma]
        let outputs = scenes.map { OutputState(name: $0.rawValue,scene: $0,palette: $0.suggestedPalette) }
        expectEqual(try SavedDesk.decode(JSONEncoder().encode(SavedDesk(outputs: outputs))).outputs,outputs)
        let leader = outputs[0]
        for output in outputs.dropFirst() {
            var follower = output
            follower.role = .coordinated
            expectEqual(follower.resolved(leader: leader).scene,output.settings.scene)
            expectEqual(follower.resolved(leader: leader).persistence,output.settings.persistence)
            expectEqual(follower.resolved(leader: leader).palette,leader.settings.palette)
            follower.role = .mirrored
            expectEqual(follower.resolved(leader: leader),leader.settings)
            follower.role = .independent
            expectEqual(follower.settings,output.settings)
            expectEqual(follower.resolved(leader: leader),output.settings)
        }
        var changed = outputs[1]; changed.settings.scene = .rain; changed.settings.persistence = 0.1
        expectEqual(outputs[0],leader)
        expectEqual(outputs[1].settings.scene,.crystal)
    }
    func testReactivityMigrationAndRoles() throws {
        var leader = OutputState(name: "Leader",scene: .galaxy,palette: .ice)
        leader.settings.intensity = 0.37; leader.settings.reactivity = 1.8
        var follower = OutputState(name: "Follower",scene: .rain,palette: .ember)
        follower.settings.reactivity = 0.2; follower.settings.persistence = 0.19; follower.quality = .native
        let phase = follower.phase
        expectEqual(follower.resolved(leader: leader).reactivity,0.2)
        follower.role = .coordinated
        expectEqual(follower.resolved(leader: leader).reactivity,1.8)
        expectEqual(follower.resolved(leader: leader).intensity,0.37)
        expectEqual(follower.resolved(leader: leader).scene,.rain)
        expectEqual(follower.resolved(leader: leader).persistence,0.19)
        expectEqual(follower.phase,phase); expectEqual(follower.quality,.native)
        follower.role = .mirrored; expectEqual(follower.resolved(leader: leader),leader.settings)
        follower.role = .independent; expectEqual(follower.resolved(leader: leader).reactivity,0.2)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedDesk(outputs: [leader,follower]))) as! [String: Any]
        var outputs = old["outputs"] as! [[String: Any]]
        for i in outputs.indices {
            var settings = outputs[i]["settings"] as! [String: Any]
            settings.removeValue(forKey: "reactivity"); outputs[i]["settings"] = settings
        }
        old["outputs"] = outputs
        let migrated = try SavedDesk.decode(JSONSerialization.data(withJSONObject: old)).outputs
        leader.settings.reactivity = 1; follower.settings.reactivity = 1
        expectEqual(migrated,[leader,follower])
        for invalid: Float in [-0.01,2.01] {
            leader.settings.reactivity = invalid
            expectThrowsError(try SavedDesk.decode(JSONEncoder().encode(SavedDesk(outputs: [leader]))))
        }
        var settings = outputs[0]["settings"] as! [String: Any]; settings["reactivity"] = NSNull()
        outputs[0]["settings"] = settings; old["outputs"] = outputs
        expectThrowsError(try SavedDesk.decode(JSONSerialization.data(withJSONObject: old)))
        leader.settings.reactivity = .infinity
        expectThrowsError(try JSONEncoder().encode(SavedDesk(outputs: [leader])))
    }
    // Feed timed blocks through the same analyzer used by captured samples.
    func feed(_ analyzer: AudioAnalyzer, start: Int, blocks: Int, amplitude: Float, frequency: Double = 93.75, air: Float = 0) -> AudioFeatures {
        var result = AudioFeatures()
        for block in 0..<blocks {
            let frames = (0..<384).map { j in
                let i = start+block*384+j
                let value = amplitude*Float(sin(Double(i)*2*Double.pi*frequency/48000)) + air*Float(sin(Double(i)*2*Double.pi*6000/48000))
                return StereoFrame(left: value,right: -value,hostTime: UInt64(i),sequence: UInt64(i))
            }
            frames.withUnsafeBufferPointer { analyzer.append($0) }
            result = analyzer.analyse(sampleRate: 48000,elapsed: 0.008,fresh: true)
        }
        return result
    }
    func testGatedSensitivityAndSpectralOnset() {
        let analyzer = AudioAnalyzer()
        let noise = feed(analyzer,start: 0,blocks: 1000,amplitude: 0.0005,frequency: 6000)
        expectLessThan(noise.high,0.0001); expectLessThan(noise.transient,0.0001)
        let noiseAnalyzer = AudioAnalyzer()
        let noiseFrames = (0..<48000).map { i in
            let value = Float((i &* 1664525 &+ 1013904223)%65536)/32768-1
            return StereoFrame(left: value*0.0007,right: -value*0.0007,hostTime: UInt64(i),sequence: UInt64(i))
        }
        noiseFrames.withUnsafeBufferPointer { noiseAnalyzer.append($0) }
        for _ in 0..<200 {
            let f = noiseAnalyzer.analyse(sampleRate: 48000,elapsed: 0.008,fresh: true)
            expectLessThan(f.high+f.bass+f.mid+f.transient,0.0001)
        }
        let earlyQuiet = feed(analyzer,start: 384000,blocks: 20,amplitude: 0.025)
        let quiet = feed(analyzer,start: 391680,blocks: 1980,amplitude: 0.025)
        expectGreaterThan(quiet.bass,earlyQuiet.bass*1.5)
        expectGreaterThan(quiet.bass,0.08); expectLessThan(quiet.bass,0.5)
        expectLessThan(quiet.transient,0.01)
        let sustained = feed(analyzer,start: 1152000,blocks: 1250,amplitude: 0.25)
        expectLessThan(sustained.transient,0.02)
        var hit: Float = 0
        for b in 0..<8 {
            let f = feed(analyzer,start: 1632000+b*384,blocks: 1,amplitude: 0.247,air: 0.04)
            hit = max(hit,f.transient)
            expectTrue([f.bass,f.mid,f.high,f.transient].allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
        expectGreaterThan(hit,0.08)
        let released = feed(analyzer,start: 1635072,blocks: 125,amplitude: 0)
        expectLessThan(released.bass,0.006); expectLessThan(released.transient,0.001)
        let restart = feed(analyzer,start: 2000000,blocks: 6,amplitude: 0.2)
        expectLessThan(restart.transient,0.01)
        let fresh = AudioAnalyzer(); let initial = feed(fresh,start: 0,blocks: 6,amplitude: 0.4)
        expectLessThan(initial.transient,0.01)
        _ = fresh.analyse(sampleRate: 48000,elapsed: 1,fresh: false)
        let afterGap = feed(fresh,start: 2304,blocks: 6,amplitude: 0.4)
        expectLessThan(afterGap.transient,0.01)
    }
    func testElapsedReleaseAndMotion() {
        let a = tone(93.75), b = tone(93.75)
        _ = a.analyse(sampleRate: 48000,elapsed: 0.05,fresh: true)
        _ = b.analyse(sampleRate: 48000,elapsed: 0.05,fresh: true)
        var fa = AudioFeatures(), fb = AudioFeatures()
        for _ in 0..<60 { fa = a.analyse(sampleRate: 48000,elapsed: 1.0/60,fresh: false) }
        for _ in 0..<120 { fb = b.analyse(sampleRate: 48000,elapsed: 1.0/120,fresh: false) }
        expectEqual(fa.bass,fb.bass,accuracy: 0.00001)
        var x: Float = 0, y: Float = 0, calm: Float = 0
        for _ in 0..<600 { x = ResponseMotion.advance(x,elapsed: 1.0/60,bass: 0.6,reactivity: 1.5) }
        for _ in 0..<1200 { y = ResponseMotion.advance(y,elapsed: 1.0/120,bass: 0.6,reactivity: 1.5) }
        for _ in 0..<600 { calm = ResponseMotion.advance(calm,elapsed: 1.0/60,bass: 0.6,reactivity: 0) }
        expectEqual(x,y,accuracy: 0.0001); expectEqual(calm,0.65,accuracy: 0.0001)
        expectEqual(ResponseMotion.advance(0,elapsed: 10,bass: 100,reactivity: 100),0.023,accuracy: 0.00001)
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
try checks.testSceneCompatibilityAndIndependentNewScenes()
try checks.testReactivityMigrationAndRoles()
checks.testGatedSensitivityAndSpectralOnset()
checks.testElapsedReleaseAndMotion()
print("11 core checks completed; \(failures) failures")
exit(failures == 0 ? 0 : 1)
