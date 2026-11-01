import SwiftUI
import AppKit
import MetalKit
import PhosphorCore

@main
struct PhosphorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var desk = DeskModel()
    var body: some SwiftUI.Scene {
        WindowGroup("Phosphor · Control desk", id: "desk") {
            DeskView(desk: desk).preferredColorScheme(.dark)
                .frame(minWidth: 740, minHeight: 620)
                .onAppear { desk.startup() }
        }
        .defaultSize(width: 920, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Add output") { desk.addOutput() }.keyboardShortcut("n") }
            CommandGroup(after: .windowArrangement) {
                Button("Control desk") { NSApp.windows.first(where: { $0.title == "Phosphor · Control desk" })?.makeKeyAndOrderFront(nil) }.keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Keep saved output settings separate from the lifetime of presentation windows.
@MainActor final class DeskModel: ObservableObject {
    @Published var outputs: [OutputState] = []
    @Published var screens: [NSScreen] = []
    @Published var status = "Capture stopped · no audio source"
    @Published var running = false
    @Published var starting = false
    @Published var musicOnly = true
    @Published var features = AudioFeatures()
    @Published var sampleRate: Double = 48000
    @Published var dropped: UInt64 = 0
    @Published var notice = ""
    @Published var tick = 0
    let audio = AudioEngine()
    var windows: [UUID: OutputWindow] = [:]
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var started = false
    private var diagnosticCount = 0
    private var presentationActivity: NSObjectProtocol?
    private let preferencesKey = "Phosphor.savedDesk.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: preferencesKey), let saved = try? SavedDesk.decode(data) { outputs = saved.outputs }
        if outputs.isEmpty {
            outputs = [OutputState(name: "Output 1", scene: .scope, palette: .mint), OutputState(name: "Output 2", scene: .bloom, palette: .ultraviolet)]
        }
        screens = NSScreen.screens
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshScreens() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func startup() {
        guard !started else { return }; started = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--stage-outputs") { for output in outputs.prefix(2) { open(output.id) } }
        if args.contains("--capture-music") { startCapture() }
    }
    func refresh() {
        let value = audio.snapshot(); features = value.0; status = value.1; sampleRate = value.2; dropped = value.3; tick += 1
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            diagnosticCount += 1
            if diagnosticCount % 5 == 0 {
                let metrics = windows.values.map { "\($0.title): fps=\(String(format: "%.1f", $0.renderer.fps)) gpu_ms=\(String(format: "%.2f", $0.renderer.gpuMilliseconds))" }.joined(separator: "; ")
                print("PHOSPHOR frames=\(features.totalFrames) rms=\(features.rms) peak=\(features.peak) bass=\(features.bass) mid=\(features.mid) high=\(features.high) drops=\(dropped) status=\(status) \(metrics)")
                fflush(stdout)
            }
        }
    }
    func startCapture() {
        starting = true; notice = ""
        audio.start(musicOnly: musicOnly) { [weak self] error in
            self?.starting = false; self?.running = error == nil
            if let error { self?.notice = error }
        }
    }
    func stopCapture() { audio.stop(); running = false }
    func addOutput() {
        guard outputs.count < 16 else { notice = "The prototype supports up to 16 output configurations."; return }
        var number = outputs.count+1
        while outputs.contains(where: {$0.name == "Output \(number)"}) { number += 1 }
        outputs.append(OutputState(name: "Output \(number)", scene: .tunnel, palette: .ember)); save()
    }
    func settings(_ id: UUID) -> (SceneSettings, Quality, Float) {
        guard let value = outputs.first(where: { $0.id == id }) else { return (SceneSettings(), .balanced, 0) }
        let leader = outputs.first
        let phase = value.role == .mirrored ? (leader?.phase ?? 0) : value.phase
        return (value.resolved(leader: leader),value.quality,phase)
    }
    func update(_ output: OutputState) {
        guard let index = outputs.firstIndex(where: { $0.id == output.id }) else { return }
        let old = outputs[index]; outputs[index] = output
        if output.screenID != old.screenID { reassign(output.id) }
        if output.role == .mirrored, let leader = outputs.first, leader.id != output.id { open(leader.id) }
        save()
    }
    func save() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(SavedDesk(outputs: outputs)), forKey: preferencesKey) }
        catch { notice = "Could not save the desk: \(error.localizedDescription)" }
    }
    func open(_ id: UUID) {
        if let window = windows[id] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        guard let output = outputs.first(where: { $0.id == id }) else { return }
        do {
            let renderer = try SceneRenderer(audio: audio) { [weak self] in self?.settings(id) ?? (SceneSettings(), .balanced, 0) }
            renderer.mirrorSource = { [weak self] in
                guard let self, self.outputs.first(where: {$0.id == id})?.role == .mirrored,
                      let leader = self.outputs.first, leader.id != id else { return nil }
                return self.windows[leader.id]?.renderer
            }
            let window = OutputWindow(name: output.name, renderer: renderer)
            window.onClose = { [weak self] in self?.outputClosed(id) }
            window.onExitFullscreen = { [weak self] in self?.reassign(id) }
            windows[id] = window
            if presentationActivity == nil {
                presentationActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Live audio-reactive presentation")
            }
            if output.role == .mirrored, let leader = outputs.first, leader.id != id { open(leader.id) }
            reassign(id); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); tick += 1
        } catch { notice = "Metal output could not start: \(error.localizedDescription)" }
    }
    func outputClosed(_ id: UUID) {
        windows.removeValue(forKey: id)
        if id == outputs.first?.id {
            for mirror in outputs where mirror.id != id && mirror.role == .mirrored { windows[mirror.id]?.close() }
        }
        if windows.isEmpty, let presentationActivity { ProcessInfo.processInfo.endActivity(presentationActivity); self.presentationActivity = nil }
        tick += 1
    }
    func close(_ id: UUID) { windows[id]?.close(); tick += 1 }
    func remove(_ id: UUID) { close(id); outputs.removeAll(where: {$0.id == id}); if !outputs.isEmpty { outputs[0].role = .independent }; save() }
    func fullscreen(_ id: UUID) { open(id); windows[id]?.toggleFullScreen(nil) }
    func reassign(_ id: UUID) {
        guard let output = outputs.first(where: {$0.id == id}), let window = windows[id] else { return }
        let screen = screens.first(where: {$0.displayID == output.screenID}) ?? NSScreen.main ?? screens.first
        guard let screen else { return }
        if window.styleMask.contains(.fullScreen) {
            notice = "Leave fullscreen before moving this output to another display. The selection is saved."
            return
        }
        let area = screen.visibleFrame
        let offset = CGFloat(outputs.firstIndex(where: {$0.id == id}) ?? 0)*36
        window.setFrame(NSRect(x: area.midX-480+offset, y: area.midY-270-offset, width: min(960,area.width), height: min(540,area.height)), display: true)
    }
    func refreshScreens() {
        screens = NSScreen.screens
        for id in windows.keys { reassign(id) }
        if notice.isEmpty { notice = "Display list changed. Outputs on unavailable screens were moved to the operator display." }
    }
}
extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

final class OutputWindow: NSWindow, NSWindowDelegate {
    let renderer: SceneRenderer
    var onClose: (() -> Void)?
    var onExitFullscreen: (() -> Void)?
    init(name: String, renderer: SceneRenderer) {
        self.renderer = renderer
        super.init(contentRect: NSRect(x: 100,y: 100,width: 960,height: 540), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        title = name; isReleasedWhenClosed = false; delegate = self
        backgroundColor = .black; collectionBehavior = [.fullScreenPrimary]
        contentView = PresentationView(renderer: renderer)
    }
    func windowWillClose(_ notification: Notification) { (contentView as? PresentationView)?.stop(); onClose?() }
    func windowDidExitFullScreen(_ notification: Notification) { titleVisibility = .visible; onExitFullscreen?() }
    func windowWillEnterFullScreen(_ notification: Notification) { titleVisibility = .hidden }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && styleMask.contains(.fullScreen) { toggleFullScreen(nil) } else { super.keyDown(with: event) }
    }
}

struct DeskView: View {
    @ObservedObject var desk: DeskModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading,spacing: 4) {
                        Text("PHOSPHOR").font(.system(size: 31, weight: .light, design: .rounded)).tracking(6)
                        Text("Sound takes shape.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("CONTROL DESK  /  01").font(.system(.caption, design: .monospaced)).foregroundStyle(.mint)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Audio source", systemImage: "waveform").font(.headline)
                        Spacer()
                        Picker("Capture", selection: $desk.musicOnly) { Text("Apple Music only").tag(true); Text("System mix").tag(false) }
                            .labelsHidden().frame(width: 200).disabled(desk.running || desk.starting)
                        Button(desk.running ? "Stop capture" : desk.starting ? "Starting…" : "Start capture") {
                            if desk.running { desk.stopCapture() } else { desk.startCapture() }
                        }.disabled(desk.starting).buttonStyle(.borderedProminent).tint(.mint)
                    }
                    Text(desk.status).font(.system(.caption, design: .monospaced)).foregroundStyle(desk.features.peak > 0.00001 ? .mint : .secondary).textSelection(.enabled)
                    HStack(spacing: 18) {
                        Meter(label: "BASS", value: desk.features.bass, color: .mint)
                        Meter(label: "MID", value: desk.features.mid, color: .purple)
                        Meter(label: "AIR", value: desk.features.high, color: .cyan)
                        Meter(label: "HIT", value: desk.features.transient, color: .orange)
                    }
                    Text("\(Int(desk.sampleRate)) Hz · stereo · \(desk.features.totalFrames) frames · \(desk.dropped) dropped · \(desk.features.discontinuities) gaps").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    Text("Grant System Audio Recording when macOS asks. A silent tap does not prove permission or protected-content capture. Audio stays in memory.").font(.caption).foregroundStyle(.secondary)
                }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                HStack { Text("Presentation outputs").font(.title3); Spacer(); Text("\(desk.screens.count) display(s)").foregroundStyle(.secondary); Button("Add output", systemImage: "plus") { desk.addOutput() } }
                ForEach(desk.outputs) { output in
                    OutputCard(output: output, desk: desk)
                }
                Text("The first output leads mirrored and coordinated roles. Mirrors show its rendered scene. Coordinated outputs share palette, intensity, audio and time; each keeps its composition. Displays present on their own refresh clocks.").font(.caption).foregroundStyle(.secondary)
                if !desk.notice.isEmpty { Text(desk.notice).foregroundStyle(.orange).font(.caption).textSelection(.enabled) }
            }.padding(28)
        }.background(Color(red: 0.035,green: 0.045,blue: 0.055))
    }
}
struct Meter: View {
    let label: String; let value: Float; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(label); Spacer(); Text(String(format: "%.2f", value)) }.font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            GeometryReader { geo in RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.13)).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: geo.size.width*CGFloat(min(1,max(0,value)))) } }.frame(height: 5)
        }
    }
}
struct OutputCard: View {
    let output: OutputState
    @ObservedObject var desk: DeskModel
    func binding<T>(_ path: WritableKeyPath<OutputState,T>) -> Binding<T> {
        Binding(get: { desk.outputs.first(where: {$0.id == output.id})?[keyPath: path] ?? output[keyPath: path] }, set: { value in
            guard var edited = desk.outputs.first(where: {$0.id == output.id}) else { return }; edited[keyPath: path] = value; desk.update(edited)
        })
    }
    var isLeader: Bool { output.id == desk.outputs.first?.id }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            HStack {
                Circle().fill(desk.windows[output.id] == nil ? Color.gray : .mint).frame(width: 7,height: 7)
                Text(output.name).font(.headline)
                if isLeader { Text("LEADER").font(.system(.caption2, design: .monospaced)).foregroundStyle(.mint) }
                Spacer()
                if let renderer = desk.windows[output.id]?.renderer { Text(String(format: "%.0f fps · %.1f ms GPU",renderer.fps,renderer.gpuMilliseconds)).font(.system(.caption,design: .monospaced)).foregroundStyle(.secondary) }
                Button(desk.windows[output.id] == nil ? "Open" : "Focus") { desk.open(output.id) }
                Button("Fullscreen") { desk.fullscreen(output.id) }
                Button("Close") { desk.close(output.id) }.disabled(desk.windows[output.id] == nil)
                Button { desk.remove(output.id) } label: { Image(systemName: "trash") }.help("Remove output configuration")
            }
            HStack {
                Picker("Scene",selection: binding(\.settings.scene)) { ForEach(Scene.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.disabled(output.role == .mirrored && !isLeader)
                Picker("Palette",selection: binding(\.settings.palette)) { ForEach(Palette.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.disabled(output.role != .independent && !isLeader)
            }
            HStack {
                Picker("Display",selection: binding(\.screenID)) {
                    Text("Operator display").tag(UInt32?.none)
                    ForEach(desk.screens,id: \.displayID) { Text($0.localizedName).tag(Optional($0.displayID)) }
                    if let id = output.screenID, !desk.screens.contains(where: {$0.displayID == id}) { Text("Unavailable display").tag(Optional(id)) }
                }
                Picker("Role",selection: binding(\.role)) { ForEach(OutputRole.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.disabled(isLeader)
                Picker("Quality",selection: binding(\.quality)) { ForEach(Quality.allCases,id: \.self) { Text($0.rawValue).tag($0) } }.disabled(output.role == .mirrored && !isLeader)
            }.font(.caption)
            HStack {
                Text("Intensity").font(.caption); Slider(value: binding(\.settings.intensity),in: 0...2).disabled(output.role != .independent && !isLeader)
                Text("Persistence").font(.caption); Slider(value: binding(\.settings.persistence),in: 0...0.96).disabled(output.role == .mirrored && !isLeader)
            }
        }.padding(18).background(.white.opacity(0.035),in: RoundedRectangle(cornerRadius: 12))
    }
}
