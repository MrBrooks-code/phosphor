import Foundation

// Saved names and shader IDs stay stable when more scenes are added.
public enum Scene: String, Codable, CaseIterable, Sendable {
    case scope = "Phosphor Scope", bloom = "Feedback Bloom", tunnel = "Vector Tunnel"
    case outrun = "Outrun Horizon", crystal = "Crystal Mandala", galaxy = "Spiral Galaxy"
    case rain = "Digital Rain", plasma = "Plasma Drift"
    public var shaderID: UInt32 {
        switch self {
        case .scope: return 0; case .bloom: return 1; case .tunnel: return 2
        case .outrun: return 3; case .crystal: return 4; case .galaxy: return 5
        case .rain: return 6; case .plasma: return 7
        }
    }
    public var suggestedPalette: Palette {
        switch self {
        case .outrun, .crystal: return .ultraviolet
        case .galaxy: return .ice
        case .rain, .scope: return .mint
        case .plasma, .tunnel: return .ember
        case .bloom: return .ultraviolet
        }
    }
}
public enum Palette: String, Codable, CaseIterable, Sendable { case mint = "Mint", ember = "Ember", ultraviolet = "Ultraviolet", ice = "Ice" }
public enum OutputRole: String, Codable, CaseIterable, Sendable { case independent = "Independent", mirrored = "Mirrored", coordinated = "Coordinated" }
public enum Quality: String, Codable, CaseIterable, Sendable {
    case economical = "Half resolution", balanced = "Up to 1080p", native = "Native pixels"
    public func scale(width: Double, height: Double) -> Double {
        switch self { case .economical: return 0.5; case .balanced: return min(1, 1920/max(width,height)); case .native: return 1 }
    }
}
public struct SceneSettings: Codable, Equatable, Sendable {
    public var scene: Scene = .scope
    public var palette: Palette = .mint
    public var intensity: Float = 1
    public var reactivity: Float = 1
    public var persistence: Float = 0.72
    public init(scene: Scene = .scope, palette: Palette = .mint) { self.scene = scene; self.palette = palette }
    private enum CodingKeys: String, CodingKey { case scene, palette, intensity, reactivity, persistence }
    // Keep all saved values. Only desks made before Reactivity receive its default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scene = try values.decode(Scene.self, forKey: .scene)
        palette = try values.decode(Palette.self, forKey: .palette)
        intensity = try values.decode(Float.self, forKey: .intensity)
        reactivity = values.contains(.reactivity) ? try values.decode(Float.self, forKey: .reactivity) : 1
        persistence = try values.decode(Float.self, forKey: .persistence)
    }
}
public struct OutputState: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var screenID: UInt32?
    public var role: OutputRole = .independent
    public var quality: Quality = .balanced
    public var settings: SceneSettings
    public init(name: String, scene: Scene = .scope, palette: Palette = .mint) {
        self.name = name; settings = SceneSettings(scene: scene, palette: palette)
    }
    // Mirrored outputs use the leader's settings and phase. Coordinated outputs share its palette, intensity, and reactivity.
    public func resolved(leader: OutputState?) -> SceneSettings {
        guard let leader, leader.id != id else { return settings }
        switch role {
        case .independent: return settings
        case .mirrored: return leader.settings
        case .coordinated:
            var value = settings; value.palette = leader.settings.palette; value.intensity = leader.settings.intensity; value.reactivity = leader.settings.reactivity
            return value
        }
    }
    public var phase: Float { Float(id.uuid.0) / 255 * 6.283185 }
}
public struct SavedDesk: Codable {
    public let version: Int
    public var outputs: [OutputState]
    public init(outputs: [OutputState]) { version = 1; self.outputs = outputs }
    public static func decode(_ data: Data) throws -> SavedDesk {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, value.outputs.count <= 16,
              Set(value.outputs.map(\.id)).count == value.outputs.count,
              value.outputs.allSatisfy({ $0.settings.intensity.isFinite && (0...2).contains($0.settings.intensity) && $0.settings.reactivity.isFinite && (0...2).contains($0.settings.reactivity) && $0.settings.persistence.isFinite && (0...0.96).contains($0.settings.persistence) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return value
    }
}

// Integrate bounded audio motion in seconds. Wrap whole cycles to retain Float precision.
public enum ResponseMotion {
    public static func advance(_ travel: Float, elapsed: Double, bass: Float, reactivity: Float) -> Float {
        let dt = Float(elapsed.isFinite ? min(max(elapsed,0),0.1) : 0)
        let energy = min(1.5,max(0,bass)*min(2,max(0,reactivity)))
        return (travel + dt * (0.065 + energy*0.11)).truncatingRemainder(dividingBy: 1)
    }
}
