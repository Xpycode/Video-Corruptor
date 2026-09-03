import Foundation

/// An explicitly supplied mapping from a two-byte local-set tag to its SMPTE UL.
///
/// Corpus fixtures may use synthetic tags, so this type deliberately does not
/// invent or infer mappings for unknown tags.
struct MXFPrimerMap: Equatable, Sendable {
    static let universalLabelByteCount = 16

    private let labelsByTag: [UInt16: Data]

    init() {
        labelsByTag = [:]
    }

    init(mappings: [UInt16: Data]) throws {
        for (tag, label) in mappings {
            guard label.count == Self.universalLabelByteCount else {
                throw MXFPrimerMapError.invalidUniversalLabelWidth(
                    tag: tag,
                    actual: UInt64(label.count),
                    required: UInt64(Self.universalLabelByteCount)
                )
            }
        }
        labelsByTag = mappings
    }

    func universalLabel(for tag: UInt16) -> Data? {
        labelsByTag[tag]
    }
}

enum MXFPrimerMapError: Error, Equatable, Sendable {
    case invalidUniversalLabelWidth(tag: UInt16, actual: UInt64, required: UInt64)
}
