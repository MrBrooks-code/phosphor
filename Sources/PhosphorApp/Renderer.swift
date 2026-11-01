import AppKit
import MetalKit
import PhosphorCore

struct GPUUniforms {
    var resolution: SIMD2<Float>
    var time: Float; var dt: Float
    var bass: Float; var mid: Float; var high: Float; var transient: Float
    var rms: Float; var intensity: Float; var persistence: Float; var phase: Float
    var scene: UInt32; var palette: UInt32; var padding = SIMD2<Float>.zero
}

// Each output owns feedback textures. All outputs read one clock and one audio snapshot.
final class SceneRenderer: NSObject {
    static let device = MTLCreateSystemDefaultDevice()
    static let epoch = ProcessInfo.processInfo.systemUptime
    private let commands: MTLCommandQueue
    private let scenePipeline: MTLRenderPipelineState
    private let tracePipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private var textures: [MTLTexture] = []
    private var front = 0
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var lastSettings: SceneSettings?
    private let slots = DispatchSemaphore(value: 3)
    private var slot = 0
    private let waveBuffers: [MTLBuffer]
    private let spectrumBuffers: [MTLBuffer]
    var mirrorSource: (() -> SceneRenderer?)?
    var state: () -> (SceneSettings, Quality, Float)
    let audio: AudioEngine
    private(set) var fps: Double = 0
    private(set) var gpuMilliseconds: Double = 0
    private var travel: Float = 0
    private var frames = 0
    private var measuredAt = ProcessInfo.processInfo.systemUptime
    init(audio: AudioEngine, state: @escaping () -> (SceneSettings, Quality, Float)) throws {
        guard let device = Self.device, let commands = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.commands = commands; self.audio = audio; self.state = state
        let source = try String(contentsOf: Bundle.module.url(forResource: "Scenes", withExtension: "metal")!, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        func pipeline(_ fragment: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreen")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        scenePipeline = try pipeline("sceneFragment", .rgba16Float)
        let trace = MTLRenderPipelineDescriptor()
        trace.vertexFunction = library.makeFunction(name: "scopeVertex")
        trace.fragmentFunction = library.makeFunction(name: "scopeFragment")
        trace.colorAttachments[0].pixelFormat = .rgba16Float
        trace.colorAttachments[0].isBlendingEnabled = true
        trace.colorAttachments[0].sourceRGBBlendFactor = .one
        trace.colorAttachments[0].destinationRGBBlendFactor = .one
        tracePipeline = try device.makeRenderPipelineState(descriptor: trace)
        presentPipeline = try pipeline("presentFragment", .bgra8Unorm)
        waveBuffers = (0..<3).map { _ in device.makeBuffer(length: 512*MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared)! }
        spectrumBuffers = (0..<3).map { _ in device.makeBuffer(length: 64*4, options: .storageModeShared)! }
        precondition(MemoryLayout<GPUUniforms>.stride == 64)
        super.init()
    }
    func draw(drawable: CAMetalDrawable) {
        guard slots.wait(timeout: .now()) == .success else { return }
        let source = mirrorSource?()
        let present = MTLRenderPassDescriptor()
        present.colorAttachments[0].texture = drawable.texture
        present.colorAttachments[0].loadAction = .dontCare
        present.colorAttachments[0].storeAction = .store
        guard let command = (source?.commands ?? commands).makeCommandBuffer() else { slots.signal(); return }
        let drawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        if let source, !source.textures.isEmpty {
            guard let encoder = command.makeRenderCommandEncoder(descriptor: present) else { slots.signal(); return }
            encoder.setRenderPipelineState(presentPipeline)
            encoder.setFragmentTexture(source.textures[1-source.front], index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
            finish(command, drawable: drawable)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now-lastTime,0.1); lastTime = now
        let (settings,quality,phase) = state()
        let scale = quality.scale(width: drawableSize.width, height: drawableSize.height)
        let width = max(16,Int(drawableSize.width*scale)), height = max(16,Int(drawableSize.height*scale))
        if textures.first?.width != width || textures.first?.height != height || lastSettings?.scene != settings.scene || lastSettings?.palette != settings.palette {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget,.shaderRead]; descriptor.storageMode = .private
            guard let a = Self.device?.makeTexture(descriptor: descriptor), let b = Self.device?.makeTexture(descriptor: descriptor) else { slots.signal(); return }
            textures = [a,b]; front = 0
            for texture in textures {
                let clear = MTLRenderPassDescriptor(); clear.colorAttachments[0].texture = texture
                clear.colorAttachments[0].loadAction = .clear; clear.colorAttachments[0].storeAction = .store
                command.makeRenderCommandEncoder(descriptor: clear)?.endEncoding()
            }
        }
        lastSettings = settings
        let feature = audio.snapshot().0
        let wave = waveBuffers[slot].contents().bindMemory(to: SIMD2<Float>.self, capacity: 512)
        for i in 0..<512 { wave[i] = SIMD2(feature.left[i],feature.right[i]) }
        feature.spectrum.withUnsafeBytes { bytes in spectrumBuffers[slot].contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count) }
        travel += Float(dt) * (0.065 + feature.bass*0.035)
        var uniforms = GPUUniforms(resolution: SIMD2(Float(width),Float(height)), time: Float(now-Self.epoch), dt: Float(dt), bass: feature.bass, mid: feature.mid, high: feature.high, transient: feature.transient, rms: feature.rms, intensity: settings.intensity, persistence: settings.persistence, phase: phase, scene: UInt32(Scene.allCases.firstIndex(of: settings.scene)!), palette: UInt32(Palette.allCases.firstIndex(of: settings.palette)!))
        uniforms.padding.x = travel
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = textures[front]
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { slots.signal(); return }
        encoder.setRenderPipelineState(scenePipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(waveBuffers[slot], offset: 0, index: 1)
        encoder.setFragmentBuffer(spectrumBuffers[slot], offset: 0, index: 2)
        encoder.setFragmentTexture(textures[1-front], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if settings.scene == .scope && feature.peak > 0.00001 {
            encoder.setRenderPipelineState(tracePipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 0)
            encoder.setVertexBuffer(waveBuffers[slot], offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 511)
        }
        encoder.endEncoding()
        guard let final = command.makeRenderCommandEncoder(descriptor: present) else { slots.signal(); return }
        final.setRenderPipelineState(presentPipeline); final.setFragmentTexture(textures[front], index: 0)
        final.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); final.endEncoding()
        front = 1-front; slot = (slot+1)%3
        finish(command, drawable: drawable)
    }
    private func finish(_ command: MTLCommandBuffer, drawable: CAMetalDrawable) {
        drawable.addPresentedHandler { [weak self] _ in
            DispatchQueue.main.async { self?.recordPresentation() }
        }
        command.present(drawable)
        command.addCompletedHandler { [weak self, slots] buffer in
            let duration = (buffer.gpuEndTime-buffer.gpuStartTime)*1000
            DispatchQueue.main.async { self?.gpuMilliseconds = duration }
            slots.signal()
        }
        command.commit()
    }
    private func recordPresentation() {
        let now = ProcessInfo.processInfo.systemUptime
        frames += 1
        if now-measuredAt >= 1 { fps = Double(frames)/(now-measuredAt); frames = 0; measuredAt = now }
    }
}
enum RendererError: Error { case unavailable }

// Receive available drawables from Core Animation. Do not wait for a drawable on the UI thread.
final class PresentationView: NSView, CAMetalDisplayLinkDelegate {
    private let metalLayer = CAMetalLayer()
    private var displayLink: CAMetalDisplayLink?
    private let renderer: SceneRenderer
    init(renderer: SceneRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        wantsLayer = true; layer = metalLayer
        metalLayer.device = SceneRenderer.device; metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true; metalLayer.maximumDrawableCount = 3
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.delegate = self
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    required init?(coder: NSCoder) { fatalError("Use init(renderer:)") }
    override func layout() { super.layout(); updateDrawableSize() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateDrawableSize() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateDrawableSize() }
    private func updateDrawableSize() {
        let size = convertToBacking(bounds).size
        metalLayer.contentsScale = window?.backingScaleFactor ?? 1
        metalLayer.drawableSize = CGSize(width: max(1,size.width), height: max(1,size.height))
    }
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        autoreleasepool { renderer.draw(drawable: update.drawable) }
    }
    func stop() { displayLink?.invalidate(); displayLink = nil }
    deinit { displayLink?.invalidate() }
}
