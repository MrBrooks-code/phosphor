import AppKit
import CoreText
import ImageIO
import PhosphorCore

// Export matched moving fixtures. The labels are part of each frame.
enum SceneMotionPreview {
    static let width = 640, height = 360, rate = 15, frames = 150
    static func passage(at seconds: Double) -> (AudioFeatures,String) {
        let gain: Float
        let label: String
        if seconds < 2 { gain = 0; label = "SILENCE" }
        else if seconds < 4 { gain = 0.20; label = "QUIET" }
        else if seconds < 7 { gain = 1.45; label = "LOUD + HITS" }
        else { gain = Float(exp(-(seconds-7)*7)); label = "RELEASE TO SILENCE" }
        var feature = SceneValidation.features(at: 12+seconds)
        feature.bass *= gain; feature.mid *= gain; feature.high *= gain
        feature.transient *= gain; feature.rms *= gain; feature.peak *= gain
        feature.spectrum = feature.spectrum.map { $0*gain }
        return (feature,label)
    }
    static func run(directory: URL) throws {
        guard let device = SceneRenderer.device else { throw RendererError.unavailable }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let baseline = try SceneFixture(device: device,v2: false)
        let preview = try SceneFixture(device: device,v2: true)
        try baseline.resize(width: width,height: height); try preview.resize(width: width,height: height)
        let gifProperties: [CFString:Any] = [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]]
        let frameProperties: [CFString:Any] = [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1/Double(rate)]]
        for scene in Scene.allCases.filter({ $0.shaderID >= 3 }) {
            let stem = "\(scene.shaderID)-\(scene.rawValue.replacingOccurrences(of: " ",with: "-"))"
            guard let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(stem+".gif") as CFURL,"com.compuserve.gif" as CFString,frames,nil) else { throw ExportError.destination }
            CGImageDestinationSetProperties(destination,gifProperties as CFDictionary)
            var travel: Float = 0
            for frame in 0..<frames {
                try autoreleasepool {
                    let seconds = Double(frame)/Double(rate)
                    let (feature,label) = passage(at: seconds)
                    travel = ResponseMotion.advance(travel,elapsed: 1/Double(rate),bass: feature.bass,reactivity: 1)
                    var u = GPUUniforms(resolution: SIMD2(Float(width),Float(height)),time: Float(12+seconds),dt: 1/Float(rate),bass: feature.bass,mid: feature.mid,high: feature.high,transient: feature.transient,rms: feature.rms,intensity: 1,persistence: 0.72,phase: 0.7,scene: scene.shaderID,palette: UInt32(Palette.allCases.firstIndex(of: scene.suggestedPalette)!))
                    u.travel = travel
                    _ = try baseline.render(uniforms: u,feature: feature,clearFeedback: frame == 0)
                    _ = try preview.render(uniforms: u,feature: feature,clearFeedback: frame == 0)
                    guard baseline.rawPixels().allSatisfy({ $0.isFinite && $0 >= 0 }),preview.rawPixels().allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw SceneValidation.ValidationError.invalidPixels(scene) }
                    let pair = try composite(left: baseline.cgImage(),right: preview.cgImage(),scene: scene,label: label)
                    CGImageDestinationAddImage(destination,pair,frameProperties as CFDictionary)
                    if [15,45,82,142].contains(frame) {
                        let url = directory.appendingPathComponent(stem+"-\(label.replacingOccurrences(of: " ",with: "-"))-pair.png")
                        guard let png = CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else { throw ExportError.destination }
                        CGImageDestinationAddImage(png,pair,nil)
                        guard CGImageDestinationFinalize(png) else { throw ExportError.finalize }
                    }
                }
            }
            guard CGImageDestinationFinalize(destination) else { throw ExportError.finalize }
            print("Exported \(stem): matched 10 s synthetic fixture, 15 fps, 640×360 per side.")
        }
        let manifest = """
        Deterministic synthetic GPU fixtures; no captured audio and no display-pacing measurement.
        Left: delivered baseline. Right: V2. Shared clock 12–22 s, phase 0.7, palette, size,
        input, Intensity 1, Reactivity 1, Persistence 0.72, integrated travel and time step.
        0–2 s silence; 2–4 s quiet; 4–7 s loud with hits; 7–10 s exponential release.
        Feedback is retained during each clip and reset between scenes and at the loop boundary.
        GIF quantization can reduce dark gradients. PNG pairs preserve the rendered frame.
        Both variants use the same fixture encoder, uniforms and presentation shader.
        """
        try manifest.write(to: directory.appendingPathComponent("FIXTURES.txt"),atomically: true,encoding: .utf8)
    }
    private static func composite(left: CGImage,right: CGImage,scene: Scene,label: String) throws -> CGImage {
        guard let context = CGContext(data: nil,width: width*2,height: height+64,bitsPerComponent: 8,bytesPerRow: width*8,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.destination }
        context.setFillColor(CGColor(gray: 0.015,alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: width*2,height: height+64))
        context.draw(left,in: CGRect(x: 0,y: 0,width: width,height: height))
        context.draw(right,in: CGRect(x: width,y: 0,width: width,height: height))
        func text(_ value: String,x: Int,y: Int,size: CGFloat) {
            let attributes: [NSAttributedString.Key:Any] = [.font:CTFontCreateWithName("Menlo" as CFString,size,nil),.foregroundColor:CGColor(gray: 0.85,alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value,attributes: attributes))
            context.textPosition = CGPoint(x: x,y: y); CTLineDraw(line,context)
        }
        text("DELIVERED / V1",x: 18,y: height+40,size: 13)
        text("PHOSPHOR / V2",x: width+18,y: height+40,size: 13)
        text("\(scene.rawValue) · SYNTHETIC · \(label)",x: 18,y: height+16,size: 12)
        context.setFillColor(CGColor(gray: 0.2,alpha: 1)); context.fill(CGRect(x: width,y: 0,width: 1,height: height))
        guard let result = context.makeImage() else { throw ExportError.destination }
        return result
    }
    enum ExportError: Error { case destination, finalize }
}
