import Foundation

/// Xoshiro256** pseudo-random number generator.
/// Value-type, deterministic, and `Sendable` — safe to pass as `inout` across corruption handlers.
struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: (UInt64, UInt64, UInt64, UInt64)

    init(seed: UInt64) {
        // Initialize state via SplitMix64 to spread a single seed across 256 bits
        var s = seed
        state.0 = Self.splitMix64(&s)
        state.1 = Self.splitMix64(&s)
        state.2 = Self.splitMix64(&s)
        state.3 = Self.splitMix64(&s)
    }

    mutating func next() -> UInt64 {
        let result = rotateLeft(state.1 &* 5, by: 7) &* 9

        let t = state.1 << 17
        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        state.2 ^= t
        state.3 = rotateLeft(state.3, by: 45)

        return result
    }

    private func rotateLeft(_ x: UInt64, by k: Int) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }

    private static func splitMix64(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
