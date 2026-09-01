import CryptoKit
import Foundation

enum SHA256HasherError: Error, Equatable, Sendable {
    case invalidChunkSize(Int)
}

enum SHA256Hasher: Sendable {
    static let defaultChunkSize = 1024 * 1024

    /// Returns the lowercase hexadecimal SHA-256 digest of a file, using bounded reads.
    static func hash(
        fileAt url: URL,
        chunkSize: Int = defaultChunkSize,
        cancellationCheck: @Sendable () throws -> Void = { try Task.checkCancellation() }
    ) throws -> String {
        guard chunkSize > 0 else {
            throw SHA256HasherError.invalidChunkSize(chunkSize)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try cancellationCheck()
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }

        try handle.close()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
