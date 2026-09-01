import Foundation

enum MXFMutationTransactionError: Error, Equatable, Sendable {
    case unequalEditLengths(offset: UInt64, original: UInt64, replacement: UInt64)
    case overlappingEdits(first: ByteSpan, second: ByteSpan)
    case editOutsideRetainedPrefix(span: ByteSpan, retainedSize: UInt64)
    case sourceSizeMismatch(expected: UInt64, actual: UInt64)
    case outputSizeMismatch(expected: UInt64, actual: UInt64)
    case originalByteMismatch(offset: UInt64)
    case replacementByteMismatch(offset: UInt64)
    case undeclaredChange(offset: UInt64)
    case byteIdenticalOutput
    case incorrectTruncationPrefix(offset: UInt64)
}

struct MXFMutationRecorder: Sendable {
    func recordEdit(
        offset: UInt64,
        original: Data,
        replacement: Data,
        field: String? = nil
    ) throws -> MXFByteEdit {
        let originalCount = try CheckedBinaryArithmetic.uint64(exactly: original.count)
        let replacementCount = try CheckedBinaryArithmetic.uint64(exactly: replacement.count)
        guard originalCount == replacementCount else {
            throw MXFMutationTransactionError.unequalEditLengths(
                offset: offset,
                original: originalCount,
                replacement: replacementCount
            )
        }
        _ = try ByteSpan(offset: offset, length: originalCount)
        return MXFByteEdit(
            offset: MXFDecimalUInt64(offset),
            originalHex: try MXFLowercaseHex(Self.hex(original)),
            replacementHex: try MXFLowercaseHex(Self.hex(replacement)),
            field: field
        )
    }

    func validateAndSort(
        edits: [MXFByteEdit],
        truncation: MXFTruncationRecord? = nil
    ) throws -> [MXFByteEdit] {
        let sorted = edits.sorted { $0.offset.value < $1.offset.value }
        var previous: ByteSpan?
        for edit in sorted {
            let original = try Self.decode(edit.originalHex)
            let replacement = try Self.decode(edit.replacementHex)
            let originalCount = try CheckedBinaryArithmetic.uint64(exactly: original.count)
            let replacementCount = try CheckedBinaryArithmetic.uint64(exactly: replacement.count)
            guard originalCount == replacementCount else {
                throw MXFMutationTransactionError.unequalEditLengths(
                    offset: edit.offset.value,
                    original: originalCount,
                    replacement: replacementCount
                )
            }
            let span = try ByteSpan(offset: edit.offset.value, length: originalCount)
            if let previous, previous.overlaps(span) {
                throw MXFMutationTransactionError.overlappingEdits(first: previous, second: span)
            }
            if let truncation, span.upperBound > truncation.retainedSize.value {
                throw MXFMutationTransactionError.editOutsideRetainedPrefix(
                    span: span,
                    retainedSize: truncation.retainedSize.value
                )
            }
            previous = span
        }
        return sorted
    }

    static func decode(_ hex: MXFLowercaseHex) throws -> Data {
        var result = Data(capacity: hex.value.count / 2)
        var index = hex.value.startIndex
        while index < hex.value.endIndex {
            let next = hex.value.index(index, offsetBy: 2)
            guard let byte = UInt8(hex.value[index..<next], radix: 16) else {
                throw MXFModelError.invalidLowercaseHex(hex.value)
            }
            result.append(byte)
            index = next
        }
        return result
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
