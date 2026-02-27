import Foundation

/// Represents a single atom (box) in an MP4/MOV container.
/// MP4 atoms are: [4 bytes size][4 bytes type][payload]
/// If size == 1, an 8-byte extended size follows the type.
/// If size == 0, the atom extends to end of file.
struct MP4Atom: Identifiable, Sendable {
    let id = UUID()
    let type: String           // 4-char code: "ftyp", "moov", "mdat", etc.
    let offset: UInt64         // Byte offset in the file
    let size: UInt64           // Total size including header
    let headerSize: UInt64     // 8 or 16 (extended size)
    var children: [MP4Atom]    // Nested atoms (for container atoms like moov, trak)

    /// Byte range of the atom's payload (after header)
    var payloadRange: Range<UInt64> {
        (offset + headerSize)..<(offset + size)
    }

    /// Byte range of the entire atom
    var totalRange: Range<UInt64> {
        offset..<(offset + size)
    }

    /// Whether this is a known container atom that holds children
    var isContainer: Bool {
        Self.containerTypes.contains(type)
    }

    /// Atom types that contain other atoms
    static let containerTypes: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl", "dinf",
        "edts", "udta", "meta", "ilst", "sinf", "schi"
    ]
}
