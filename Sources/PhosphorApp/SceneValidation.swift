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
        guard let device = SceneRenderer.device, let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let library = try SceneRenderer.shaderLibrary(device: device)
        func pipeline(_ name: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreen")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            descriptor.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let scenePipeline = try pipeline("sceneFragment",.rgba16Float)
        let presentPipeline = try pipeline("presentFragment",.rgba8Unorm)
        let spectrum = device.makeBuffer(length: 64*4,options: .storageModeShared)!
        let wave = device.makeBuffer(length: 512*8,options: .storageModeShared)!
        var report = "Synthetic native shader checks on \(device.name)\nGPU command duration excludes display pacing.\n"
        func texture(_ width: Int, _ height: Int, _ format: MTLPixelFormat) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,width: width,height: height,mipmapped: false)
            descriptor.usage = [.renderTarget,.shaderRead]
            descriptor.storageMode = device.supportsFamily(.apple1) ? .shared : .managed
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw ValidationError.textureUnavailable }
            return texture
        }
        for scene in Scene.allCases where scene.shaderID >= 3 {
            var quietPixels: [UInt8] = [], combinedPixels: [UInt8] = []
            for (width,height) in [(640,360),(1920,1080),(3840,2160),(2160,3840)] {
                let current = try texture(width,height,.rgba16Float), previous = try texture(width,height,.rgba16Float)
                let image = try texture(width,height,.rgba8Unorm)
                var durations: [Double] = []
                // Reuse textures and clear feedback for each isolated fixture.
                for frame in 0..<12 {
                    var feature: AudioFeatures = frame == 0 ? AudioFeatures() : features(at: 12)
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
                    feature.spectrum.withUnsafeBytes { spectrum.contents().copyMemory(from: $0.baseAddress!,byteCount: $0.count) }
                    var u = GPUUniforms(resolution: SIMD2(Float(width),Float(height)),time: 12,dt: 1/60,
                        bass: feature.bass,mid: feature.mid,high: feature.high,transient: feature.transient,
                        rms: feature.rms,intensity: 1,persistence: 0.72,phase: 0.7,scene: scene.shaderID,
                        palette: UInt32(Palette.allCases.firstIndex(of: scene.suggestedPalette)!))
                    u.padding.x = 0.8
                    if width == 640 && frame == 6 { u.intensity = 0 }
                    if width == 640 {
                        if frame == 7 { u.palette = (u.palette+1)%4 }
                        if frame == 8 { u.time = 13 }
                        if frame == 9 { u.phase = 1.7 }
                        if frame == 10 { u.palette = (u.palette+2)%4 }
                        if frame == 11 { u.palette = (u.palette+3)%4 }
                    }
                    let command = queue.makeCommandBuffer()!
                    let clear = MTLRenderPassDescriptor(); clear.colorAttachments[0].texture = previous
                    clear.colorAttachments[0].loadAction = .clear; clear.colorAttachments[0].storeAction = .store
                    command.makeRenderCommandEncoder(descriptor: clear)!.endEncoding()
                    let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = current
                    pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
                    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
                    encoder.setRenderPipelineState(scenePipeline)
                    encoder.setFragmentBytes(&u,length: MemoryLayout<GPUUniforms>.stride,index: 0)
                    encoder.setFragmentBuffer(wave,offset: 0,index: 1); encoder.setFragmentBuffer(spectrum,offset: 0,index: 2)
                    encoder.setFragmentTexture(previous,index: 0)
                    encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3); encoder.endEncoding()
                    pass.colorAttachments[0].texture = image
                    let final = command.makeRenderCommandEncoder(descriptor: pass)!
                    final.setRenderPipelineState(presentPipeline); final.setFragmentTexture(current,index: 0)
                    final.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3); final.endEncoding()
                    // Make managed GPU writes visible to CPU readback on non-Apple GPUs.
                    if current.storageMode == .managed && (width == 640 || frame == 1) {
                        guard let blit = command.makeBlitCommandEncoder() else { throw ValidationError.encoderUnavailable }
                        blit.synchronize(resource: current); blit.synchronize(resource: image); blit.endEncoding()
                    }
                    command.commit(); command.waitUntilCompleted()
                    if let error = command.error { throw error }
                    durations.append((command.gpuEndTime-command.gpuStartTime)*1000)
                    if width == 640 || frame == 1 {
                        var raw = [Float16](repeating: 0,count: width*height*4)
                        current.getBytes(&raw,bytesPerRow: width*8,from: MTLRegionMake2D(0,0,width,height),mipmapLevel: 0)
                        guard raw.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ValidationError.invalidPixels(scene) }
                        var pixels = [UInt8](repeating: 0,count: width*height*4)
                        image.getBytes(&pixels,bytesPerRow: width*4,from: MTLRegionMake2D(0,0,width,height),mipmapLevel: 0)
                        if frame == 0 { quietPixels = pixels }
                        else if width == 640 {
                            if frame == 1 { combinedPixels = pixels }
                            let baseline = frame >= 7 ? combinedPixels : quietPixels
                            let changed = zip(pixels,baseline).filter { abs(Int($0)-Int($1)) > 2 }.count
                            if frame == 6 {
                                guard pixels.enumerated().allSatisfy({ $0.offset%4 == 3 || $0.element == 0 }) else { throw ValidationError.invalidPixels(scene) }
                            } else if frame == 5 && scene == .outrun {
                                guard changed == 0 else { throw ValidationError.invalidPixels(scene) }
                            } else {
                                guard changed > 30 else { throw ValidationError.noResponse(scene) }
                            }
                            let labels = ["silence","combined","bass","mid","high","hit","zero intensity","alternate palette 1","time","phase","alternate palette 2","alternate palette 3"]
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
                report += String(format: "%@ %dx%d: median %.3f ms, max %.3f ms GPU (10 warm samples)\n",scene.rawValue,width,height,samples[samples.count/2],samples.last!)
            }
        }
        try report.write(to: directory.appendingPathComponent("shader-checks.txt"),atomically: true,encoding: .utf8)
        print(report)
    }
    enum ValidationError: Error { case noResponse(Scene), invalidPixels(Scene), textureUnavailable, encoderUnavailable }
}
