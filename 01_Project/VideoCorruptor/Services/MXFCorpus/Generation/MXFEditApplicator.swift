import Foundation

struct MXFEditApplicator: Sendable {
    func apply(
        edits: [MXFByteEdit],
        truncation: MXFTruncationRecord? = nil,
        to url: URL
    ) throws {
        let edits = try MXFMutationRecorder().validateAndSort(edits: edits, truncation: truncation)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        if let truncation, truncation.originalSize.value != fileSize {
            throw MXFMutationTransactionError.sourceSizeMismatch(
                expected: truncation.originalSize.value,
                actual: fileSize
            )
        }

        var replacements: [(offset: UInt64, bytes: Data)] = []
        replacements.reserveCapacity(edits.count)
        for edit in edits {
            let expected = try MXFMutationRecorder.decode(edit.originalHex)
            let span = try ByteSpan(
                offset: edit.offset.value,
                length: CheckedBinaryArithmetic.uint64(exactly: expected.count)
            )
            guard span.upperBound <= fileSize else {
                throw MXFMutationTransactionError.originalByteMismatch(offset: edit.offset.value)
            }
            try handle.seek(toOffset: span.lowerBound)
            guard try handle.read(upToCount: expected.count) == expected else {
                throw MXFMutationTransactionError.originalByteMismatch(offset: edit.offset.value)
            }
            replacements.append((edit.offset.value, try MXFMutationRecorder.decode(edit.replacementHex)))
        }

        for replacement in replacements {
            try handle.seek(toOffset: replacement.offset)
            try handle.write(contentsOf: replacement.bytes)
        }
        if let truncation {
            try handle.truncate(atOffset: truncation.retainedSize.value)
        }
        try handle.synchronize()
    }
}
