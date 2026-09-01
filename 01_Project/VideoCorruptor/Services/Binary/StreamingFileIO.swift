import Foundation

enum StreamingFileIOError: Error, Equatable, Sendable {
    case invalidChunkSize(Int)
    case sourceAndDestinationAreSame
    case destinationAlreadyExists
    case unableToCreateDestination
}

enum StreamingFileIO: Sendable {
    static let defaultChunkSize = 1024 * 1024

    /// Copies a file without loading it into memory. The destination is removed if
    /// the operation does not complete, including when cancellation is requested.
    @discardableResult
    static func copy(
        from sourceURL: URL,
        to destinationURL: URL,
        chunkSize: Int = defaultChunkSize,
        cancellationCheck: @Sendable () throws -> Void = { try Task.checkCancellation() }
    ) throws -> UInt64 {
        guard chunkSize > 0 else {
            throw StreamingFileIOError.invalidChunkSize(chunkSize)
        }

        let source = sourceURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        guard source != destination else {
            throw StreamingFileIOError.sourceAndDestinationAreSame
        }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw StreamingFileIOError.destinationAlreadyExists
        }

        // Open the source before creating anything at the destination.
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { try? sourceHandle.close() }

        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw StreamingFileIOError.unableToCreateDestination
        }

        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: destination)
            }
        }

        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer { try? destinationHandle.close() }

        var copiedByteCount: UInt64 = 0
        while true {
            try cancellationCheck()
            guard let chunk = try sourceHandle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }

            try destinationHandle.write(contentsOf: chunk)
            copiedByteCount = try CheckedBinaryArithmetic.add(
                copiedByteCount,
                UInt64(chunk.count)
            )
        }

        try destinationHandle.close()
        try sourceHandle.close()
        completed = true
        return copiedByteCount
    }
}
