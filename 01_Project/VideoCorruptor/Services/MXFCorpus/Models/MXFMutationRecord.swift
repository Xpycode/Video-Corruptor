import Foundation

struct MXFByteEdit: Codable, Equatable, Sendable {
    let offset: MXFDecimalUInt64
    let originalHex: MXFLowercaseHex
    let replacementHex: MXFLowercaseHex
    let field: String?
}

struct MXFTruncationRecord: Codable, Equatable, Sendable {
    let originalSize: MXFDecimalUInt64
    let retainedSize: MXFDecimalUInt64
    let containingElement: String?
    let boundary: String

    init(
        originalSize: UInt64,
        retainedSize: UInt64,
        containingElement: String?,
        boundary: String
    ) throws {
        guard retainedSize < originalSize else {
            throw MXFModelError.invalidTruncation(
                originalSize: originalSize,
                retainedSize: retainedSize
            )
        }
        self.originalSize = MXFDecimalUInt64(originalSize)
        self.retainedSize = MXFDecimalUInt64(retainedSize)
        self.containingElement = containingElement
        self.boundary = boundary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            originalSize: container.decode(MXFDecimalUInt64.self, forKey: .originalSize).value,
            retainedSize: container.decode(MXFDecimalUInt64.self, forKey: .retainedSize).value,
            containingElement: container.decodeIfPresent(String.self, forKey: .containingElement),
            boundary: container.decode(String.self, forKey: .boundary)
        )
    }
}

enum MXFSemanticIntegerKind: String, Codable, Sendable {
    case unsigned
    case signed
}

struct MXFSemanticValue: Codable, Equatable, Sendable {
    let field: String
    let kind: MXFSemanticIntegerKind
    let original: String
    let replacement: String

    init(
        field: String,
        kind: MXFSemanticIntegerKind,
        original: String,
        replacement: String
    ) throws {
        try Self.validate(original, kind: kind)
        try Self.validate(replacement, kind: kind)
        self.field = field
        self.kind = kind
        self.original = original
        self.replacement = replacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            field: container.decode(String.self, forKey: .field),
            kind: container.decode(MXFSemanticIntegerKind.self, forKey: .kind),
            original: container.decode(String.self, forKey: .original),
            replacement: container.decode(String.self, forKey: .replacement)
        )
    }

    private static func validate(_ value: String, kind: MXFSemanticIntegerKind) throws {
        switch kind {
        case .unsigned:
            _ = try MXFDecimalUInt64(decimalString: value)
        case .signed:
            let magnitude = value.hasPrefix("-") ? String(value.dropFirst()) : value
            let canonical = value == "0" ||
                (value.first != "+" && value != "-0" &&
                    !magnitude.isEmpty && magnitude.first != "0" &&
                    magnitude.allSatisfy { $0 >= "0" && $0 <= "9" })
            guard canonical, Int64(value) != nil else {
                throw MXFModelError.invalidSignedDecimal(value)
            }
        }
    }
}

struct MXFMutationRecord: Codable, Equatable, Sendable {
    let targetOffset: MXFDecimalUInt64
    let targetClassification: String
    let edits: [MXFByteEdit]
    let truncation: MXFTruncationRecord?
    let semanticValues: [MXFSemanticValue]
}
