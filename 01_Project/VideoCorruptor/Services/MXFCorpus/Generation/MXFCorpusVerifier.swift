import Foundation

struct MXFVerificationContext: Sendable {
    let sourceURL: URL
    let outputURL: URL
    let edits: [MXFByteEdit]
    let truncation: MXFTruncationRecord?
}

typealias MXFPostcondition = @Sendable (MXFVerificationContext) throws -> Void

struct MXFCorpusVerifier: Sendable {
    let chunkSize: Int

    init(chunkSize: Int = 64 * 1024) {
        self.chunkSize = max(1, chunkSize)
    }

    func verify(
        sourceURL: URL,
        outputURL: URL,
        edits: [MXFByteEdit],
        truncation: MXFTruncationRecord? = nil,
        postconditions: [MXFPostcondition] = []
    ) throws {
        let edits = try MXFMutationRecorder().validateAndSort(edits: edits, truncation: truncation)
        let source = try FileHandle(forReadingFrom: sourceURL)
        defer { try? source.close() }
        let output = try FileHandle(forReadingFrom: outputURL)
        defer { try? output.close() }
        let sourceSize = try source.seekToEnd()
        let outputSize = try output.seekToEnd()

        if let truncation {
            guard sourceSize == truncation.originalSize.value else {
                throw MXFMutationTransactionError.sourceSizeMismatch(expected: truncation.originalSize.value, actual: sourceSize)
            }
            guard outputSize == truncation.retainedSize.value else {
                throw MXFMutationTransactionError.outputSizeMismatch(expected: truncation.retainedSize.value, actual: outputSize)
            }
        } else {
            guard outputSize == sourceSize else {
                throw MXFMutationTransactionError.outputSizeMismatch(expected: sourceSize, actual: outputSize)
            }
        }

        try source.seek(toOffset: 0)
        try output.seek(toOffset: 0)
        var offset: UInt64 = 0
        var editIndex = 0
        var changed = sourceSize != outputSize
        while offset < outputSize {
            try Task.checkCancellation()
            let count = Int(min(UInt64(chunkSize), outputSize - offset))
            guard let sourceChunk = try source.read(upToCount: count), sourceChunk.count == count,
                  let outputChunk = try output.read(upToCount: count), outputChunk.count == count else {
                throw MXFMutationTransactionError.incorrectTruncationPrefix(offset: offset)
            }
            for index in 0..<count {
                let absolute = offset + UInt64(index)
                while editIndex < edits.count {
                    let editLength = UInt64(try MXFMutationRecorder.decode(edits[editIndex].originalHex).count)
                    if absolute < edits[editIndex].offset.value + editLength { break }
                    editIndex += 1
                }
                let sourceByte = sourceChunk[index]
                let outputByte = outputChunk[index]
                if editIndex < edits.count {
                    let edit = edits[editIndex]
                    let original = try MXFMutationRecorder.decode(edit.originalHex)
                    let replacement = try MXFMutationRecorder.decode(edit.replacementHex)
                    if absolute >= edit.offset.value {
                        let relative = Int(absolute - edit.offset.value)
                        guard sourceByte == original[relative] else {
                            throw MXFMutationTransactionError.originalByteMismatch(offset: absolute)
                        }
                        guard outputByte == replacement[relative] else {
                            throw MXFMutationTransactionError.replacementByteMismatch(offset: absolute)
                        }
                        changed = changed || sourceByte != outputByte
                        continue
                    }
                }
                guard sourceByte == outputByte else {
                    if truncation != nil {
                        throw MXFMutationTransactionError.incorrectTruncationPrefix(offset: absolute)
                    }
                    throw MXFMutationTransactionError.undeclaredChange(offset: absolute)
                }
            }
            offset += UInt64(count)
        }
        guard changed else { throw MXFMutationTransactionError.byteIdenticalOutput }

        let context = MXFVerificationContext(
            sourceURL: sourceURL,
            outputURL: outputURL,
            edits: edits,
            truncation: truncation
        )
        for postcondition in postconditions { try postcondition(context) }
    }
}
