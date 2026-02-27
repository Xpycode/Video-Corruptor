import Foundation

/// Formats seeds as 8-character uppercase hex strings for display and parsing.
enum SeedFormatting {

    /// Format a UInt64 seed as 8-char uppercase hex (lower 32 bits).
    static func format(_ seed: UInt64) -> String {
        String(format: "%08X", UInt32(truncatingIfNeeded: seed))
    }

    /// Parse an 8-char hex string back to UInt64. Returns nil if invalid.
    static func parse(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 8,
              let value = UInt64(trimmed, radix: 16) else {
            return nil
        }
        return value
    }

    /// Generate a random seed.
    static func randomSeed() -> UInt64 {
        UInt64.random(in: 0...UInt64(UInt32.max))
    }
}
