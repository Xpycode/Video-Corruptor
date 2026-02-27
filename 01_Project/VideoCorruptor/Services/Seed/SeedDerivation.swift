import Foundation

/// Derives independent sub-seeds from a master seed + string key.
/// Uses FNV-1a hashing so each corruption type gets its own deterministic RNG stream.
enum SeedDerivation {

    /// Derive a sub-seed from master seed and a string key (e.g. corruption type rawValue).
    static func derive(master: UInt64, key: String) -> UInt64 {
        // FNV-1a 64-bit hash of key bytes mixed with master seed
        var hash: UInt64 = 0xCBF29CE484222325 ^ master
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001B3
        }
        // Final SplitMix64 mixing pass for better avalanche
        return splitmix(hash)
    }

    /// Create a SeededRNG for a specific corruption type.
    static func rng(master: UInt64, for type: CorruptionType) -> SeededRNG {
        SeededRNG(seed: derive(master: master, key: type.rawValue))
    }

    private static func splitmix(_ seed: UInt64) -> UInt64 {
        var z = seed &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
