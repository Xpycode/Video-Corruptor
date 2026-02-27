import Foundation

/// A single KLV (Key-Length-Value) element parsed from an MXF file.
struct MXFElement: Sendable {
    let key: Data              // 16-byte SMPTE UL key
    let keyOffset: UInt64      // Byte offset of the key in the file
    let valueOffset: UInt64    // Byte offset where the value starts
    let valueLength: UInt64    // Length of the value payload
    let berHeaderSize: Int     // Number of bytes used by the BER length encoding
    let classification: MXFKeyClass

    /// Total size of this KLV triplet in bytes.
    var totalSize: UInt64 {
        16 + UInt64(berHeaderSize) + valueLength
    }
}

/// Classification of MXF UL keys by their role.
enum MXFKeyClass: Sendable {
    case partitionPack       // Header, body, footer partition packs
    case pictureEssence      // Video frame data
    case soundEssence        // Audio frame data
    case dataEssence         // Data/ancillary essence
    case indexTable           // Index table segments
    case rip                  // Random Index Pack (file footer)
    case fillItem             // KLV fill / padding
    case other                // Everything else (metadata sets, etc.)
}

/// Parsed MXF partition pack header.
struct MXFPartitionPack: Sendable {
    let element: MXFElement
    let majorVersion: UInt16
    let minorVersion: UInt16
    let kagSize: UInt32
    let thisPartitionOffset: UInt64
    let previousPartitionOffset: UInt64
    let footerPartitionOffset: UInt64
    let headerByteCount: UInt64
    let indexByteCount: UInt64
    let bodyOffset: UInt64

    /// Whether this is the header partition (first in file).
    var isHeader: Bool { thisPartitionOffset == 0 }
}
