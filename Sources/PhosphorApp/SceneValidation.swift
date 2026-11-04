import AppKit
import MetalKit
import PhosphorCore

// Render repeatable shader fixtures on the real GPU. These are not capture or presentation tests.
enum SceneValidation {
    static func features(at time: Double) -> AudioFeatures {
        let t = Float(time)
        var value = AudioFeatures()
        value.bass = 0.32+0.24*sin(t*2.1)
        value.mid = 0.28+0.2*sin(t*1.3+1)
        value.high = 0.22+0.18*sin(t*3.2+2)
        value.transient = pow(max(0,sin(t*3.8)),14)*0.7
        value.rms = 0.2; value.peak = 0.4
        value.spectrum = (0..<64).map { i in 0.16+0.14*sin(Float(i)*0.4+t*1.7) }
        return value
    }
    static func run(directory: URL) throws {
        guard let device = SceneRenderer.device else { throw RendererError.unavailable }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let fixture = try SceneFixture(device: device)
        var report = "Synthetic native shader checks on \(device.name)\nGPU command duration excludes display pacing.\n"
        for scene in Scene.allCases {
            var quietPixels: [UInt8] = [], combinedPixels: [UInt8] = [], calmPixels: [UInt8] = []
            var combinedRaw: [Float16] = []
            for (width,height) in [(640,360),(1920,1080),(3840,2160),(2160,3840)] {
                try fixture.resize(width: width,height: height)
                var durations: [Double] = []
                // Reuse textures and clear feedback for each isolated fixture.
                for frame in 0..<(width == 640 ? 16 : 12) {
                    var feature: AudioFeatures = (frame == 0 || frame == 13) ? AudioFeatures() : features(at: 12)
                    if width == 640 && (2...5).contains(frame) {
                        feature = AudioFeatures()
                        if frame == 2 { feature.bass = 0.8 }
                        if frame == 3 { feature.mid = 0.8 }
                        if frame == 4 { feature.high = 0.8 }
                        if frame == 5 { feature.transient = 0.8 }
                        if frame < 5 {
                            let start = (frame-2)*21
                            for band in start..<min(start+21,64) { feature.spectrum[band] = 0.8 }
                        }
                    }
                    var u = GPUUniforms(resolution: SIMD2(Float(width),Float(height)),time: 12,dt: 1/60,
                        bass: feature.bass,mid: feature.mid,high: feature.high,transient: feature.transient,
                        rms: feature.rms,intensity: 1,persistence: 0.72,phase: 0.7,scene: scene.shaderID,
                        palette: UInt32(Palette.allCases.firstIndex(of: scene.suggestedPalette)!))
                    u.travel = 0.8
                    if width == 640 && frame == 6 { u.intensity = 0 }
                    if width == 640 {
                        if frame == 7 { u.palette = (u.palette+1)%4 }
                        if frame == 8 { u.time = 13 }
                        if frame == 9 { u.phase = 1.7 }
                        if frame == 10 { u.palette = (u.palette+2)%4 }
                        if frame == 11 { u.palette = (u.palette+3)%4 }
                        if frame == 12 || frame == 13 { u.reactivity = 0 }
                        if frame == 14 { u.reactivity = 2 }
                        if frame == 15 { u.intensity = 0.5 }
                    }
                    durations.append(try fixture.render(uniforms: u,feature: feature,clearFeedback: true))
                    if width == 640 || frame == 1 {
                        let raw = fixture.rawPixels()
                        guard raw.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ValidationError.invalidPixels(scene) }
                        let pixels = fixture.pixels()
                        if frame == 0 { quietPixels = pixels }
                        else if width == 640 {
                            if frame == 1 { combinedPixels = pixels; combinedRaw = raw }
                            if frame == 12 { calmPixels = pixels }
                            if frame == 13 && scene != .scope {
                                guard pixels == calmPixels else { throw ValidationError.invalidPixels(scene) }
                            }
                            if frame == 14 {
                                // A scalar exposure change cannot satisfy this shape test.
                                let colors = zip(raw,combinedRaw).enumerated().filter { $0.offset%4 != 3 }.map(\.element)
                                let energy = colors.reduce(0.0) { $0 + Double($1.1)*Double($1.1) }
                                let fit = colors.reduce(0.0) { $0 + Double($1.0)*Double($1.1) }/max(energy,0.00001)
                                let residual = colors.reduce(0.0) { $0 + pow(Double($1.0)-Double($1.1)*fit,2) }
                                guard residual/max(energy,0.00001) > 0.0001 else { throw ValidationError.noResponse(scene) }
                            }
                            if frame == 15 {
                                guard zip(raw,combinedRaw).enumerated().allSatisfy({ $0.offset%4 == 3 || abs(Float($0.element.0)-Float($0.element.1)*0.5) < 0.004 }) else { throw ValidationError.invalidPixels(scene) }
                            }
                            let baseline = frame >= 7 ? combinedPixels : quietPixels
                            let changed = zip(pixels,baseline).filter { abs(Int($0)-Int($1)) > 2 }.count
                            if frame == 6 {
                                guard pixels.enumerated().allSatisfy({ $0.offset%4 == 3 || $0.element == 0 }) else { throw ValidationError.invalidPixels(scene) }
                            } else if (frame == 5 && scene == .scope) || (scene == .scope && (frame == 8 || frame == 9)) {
                                guard changed == 0 else { throw ValidationError.invalidPixels(scene) }
                            } else if frame != 13 {
                                guard changed > 30 else { throw ValidationError.noResponse(scene) }
                            }
                            let labels = ["silence","combined","bass","mid","high","hit","zero intensity","alternate palette 1","time","phase","alternate palette 2","alternate palette 3","zero reactivity","silence at zero reactivity","strong reactivity","half intensity"]
                            report += "\(scene.rawValue) \(labels[frame]): \(changed) channels changed from \(frame >= 7 ? "combined" : "silence").\n"
                        } else {
                            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: width,pixelsHigh: height,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: width*4,bitsPerPixel: 32)!
                            pixels.withUnsafeBytes { bitmap.bitmapData!.update(from: $0.baseAddress!.assumingMemoryBound(to: UInt8.self),count: pixels.count) }
                            let suffix = width == 2160 ? "-portrait" : (width == 3840 ? "-4k" : "")
                            try bitmap.representation(using: .png,properties: [:])!.write(to: directory.appendingPathComponent("\(scene.shaderID)-\(scene.rawValue.replacingOccurrences(of: " ",with: "-"))\(suffix).png"))
                        }
                    }
                }
                let samples = durations.dropFirst(2).sorted()
                report += String(format: "%@ %dx%d: median %.3f ms, max %.3f ms GPU (%d warm samples)\n",scene.rawValue,width,height,samples[samples.count/2],samples.last!,samples.count)
            }
        }
        try report.write(to: directory.appendingPathComponent("shader-checks.txt"),atomically: true,encoding: .utf8)
        print(report)
    }
    enum ValidationError: Error { case noResponse(Scene), invalidPixels(Scene), textureUnavailable, encoderUnavailable }
}

// Share one offscreen render path between pixel checks and matched motion exports.
final class SceneFixture {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let scenePipeline: MTLRenderPipelineState
    let presentPipeline: MTLRenderPipelineState
    let tracePipeline: MTLRenderPipelineState
    let spectrum: MTLBuffer
    let wave: MTLBuffer
    var current: MTLTexture!
    var previous: MTLTexture!
    var image: MTLTexture!
    init(device: MTLDevice, v2: Bool? = nil) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.queue = queue
        let library = try SceneRenderer.shaderLibrary(device: device,v2: v2)
        func pipeline(_ name: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreen")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            descriptor.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        scenePipeline = try pipeline("sceneFragment",.rgba16Float)
        presentPipeline = try pipeline("presentFragment",.rgba8Unorm)
        let trace = MTLRenderPipelineDescriptor()
        trace.vertexFunction = library.makeFunction(name: "scopeVertex")
        trace.fragmentFunction = library.makeFunction(name: "scopeFragment")
        trace.colorAttachments[0].pixelFormat = .rgba16Float
        trace.colorAttachments[0].isBlendingEnabled = true
        trace.colorAttachments[0].sourceRGBBlendFactor = .one
        trace.colorAttachments[0].destinationRGBBlendFactor = .one
        tracePipeline = try device.makeRenderPipelineState(descriptor: trace)
        spectrum = device.makeBuffer(length: 64*4,options: .storageModeShared)!
        wave = device.makeBuffer(length: 512*8,options: .storageModeShared)!
        let points = wave.contents().bindMemory(to: SIMD2<Float>.self,capacity: 512)
        for i in 0..<512 { points[i] = SIMD2(sin(Float(i)*0.05)*0.25,sin(Float(i)*0.07)*0.2) }
    }
    func resize(width: Int,height: Int) throws {
        guard current?.width != width || current?.height != height else { return }
        current = try texture(width,height,.rgba16Float)
        previous = try texture(width,height,.rgba16Float)
        image = try texture(width,height,.rgba8Unorm)
    }
    private func texture(_ width: Int, _ height: Int, _ format: MTLPixelFormat) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,width: width,height: height,mipmapped: false)
        descriptor.usage = [.renderTarget,.shaderRead]
        descriptor.storageMode = device.supportsFamily(.apple1) ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw SceneValidation.ValidationError.textureUnavailable }
        return texture
    }
    func render(uniforms: GPUUniforms, feature: AudioFeatures, clearFeedback: Bool) throws -> Double {
        var u = uniforms
        feature.spectrum.withUnsafeBytes { spectrum.contents().copyMemory(from: $0.baseAddress!,byteCount: $0.count) }
        let command = queue.makeCommandBuffer()!
        if clearFeedback {
            let clear = MTLRenderPassDescriptor(); clear.colorAttachments[0].texture = previous
            clear.colorAttachments[0].loadAction = .clear; clear.colorAttachments[0].storeAction = .store
            command.makeRenderCommandEncoder(descriptor: clear)!.endEncoding()
        }
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = current
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(scenePipeline)
        encoder.setFragmentBytes(&u,length: MemoryLayout<GPUUniforms>.stride,index: 0)
        encoder.setFragmentBuffer(wave,offset: 0,index: 1); encoder.setFragmentBuffer(spectrum,offset: 0,index: 2)
        encoder.setFragmentTexture(previous,index: 0)
        encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3)
        if u.scene == 0 && feature.peak > 0 {
            encoder.setRenderPipelineState(tracePipeline)
            encoder.setVertexBytes(&u,length: MemoryLayout<GPUUniforms>.stride,index: 0)
            encoder.setVertexBuffer(wave,offset: 0,index: 1)
            encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 6,instanceCount: 511)
        }
        encoder.endEncoding()
        pass.colorAttachments[0].texture = image
        let final = command.makeRenderCommandEncoder(descriptor: pass)!
        final.setRenderPipelineState(presentPipeline); final.setFragmentTexture(current,index: 0)
        final.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3); final.endEncoding()
        // Make managed GPU writes visible to CPU readback on non-Apple GPUs.
        if current.storageMode == .managed {
            guard let blit = command.makeBlitCommandEncoder() else { throw SceneValidation.ValidationError.encoderUnavailable }
            blit.synchronize(resource: current); blit.synchronize(resource: image); blit.endEncoding()
        }
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        swap(&current,&previous)
        return (command.gpuEndTime-command.gpuStartTime)*1000
    }
    func rawPixels() -> [Float16] {
        var raw = [Float16](repeating: 0,count: image.width*image.height*4)
        previous.getBytes(&raw,bytesPerRow: image.width*8,from: MTLRegionMake2D(0,0,image.width,image.height),mipmapLevel: 0)
        return raw
    }
    func pixels() -> [UInt8] {
        var pixels = [UInt8](repeating: 0,count: image.width*image.height*4)
        image.getBytes(&pixels,bytesPerRow: image.width*4,from: MTLRegionMake2D(0,0,image.width,image.height),mipmapLevel: 0)
        return pixels
    }
    func cgImage() throws -> CGImage {
        let data = Data(pixels())
        guard let provider = CGDataProvider(data: data as CFData),
              let result = CGImage(width: image.width,height: image.height,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: image.width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent) else { throw SceneValidation.ValidationError.textureUnavailable }
        return result
    }
}
