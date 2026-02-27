import Foundation

/// Carries per-corruption state through handler calls.
/// Passed as `inout` — value type, no shared state, Swift 6 safe.
struct CorruptionContext: Sendable {
    var rng: SeededRNG
    var severity: CorruptionSeverity
    var mode: CorruptionMode

    init(rng: SeededRNG, severity: CorruptionSeverity = .moderate, mode: CorruptionMode = .individual) {
        self.rng = rng
        self.severity = severity
        self.mode = mode
    }
}

/// How corruptions are applied to output files.
enum CorruptionMode: String, Sendable {
    case individual
    case stacked
}

/// Corruption intensity. Full implementation in Wave 2.
struct CorruptionSeverity: Sendable {
    let intensity: Double

    static let subtle = CorruptionSeverity(intensity: 0.15)
    static let moderate = CorruptionSeverity(intensity: 0.5)
    static let heavy = CorruptionSeverity(intensity: 0.8)
    static let extreme = CorruptionSeverity(intensity: 1.0)
}
