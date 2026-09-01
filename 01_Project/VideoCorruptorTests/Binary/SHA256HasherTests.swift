import Foundation
import Synchronization
import XCTest
@testable import VideoCorruptor

final class SHA256HasherTests: XCTestCase {
    func testEmptyAndKnownVectors() throws {
        try withTemporaryDirectory { directory in
            let empty = directory.appendingPathComponent("empty")
            let abc = directory.appendingPathComponent("abc")
            try Data().write(to: empty)
            try Data("abc".utf8).write(to: abc)

            XCTAssertEqual(
                try SHA256Hasher.hash(fileAt: empty, chunkSize: 1),
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
            XCTAssertEqual(
                try SHA256Hasher.hash(fileAt: abc, chunkSize: 2),
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )
        }
    }

    func testMultiChunkDigestIsIndependentOfChunkSize() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("pattern")
            try Data((0..<65_537).map { UInt8(($0 * 17) % 256) }).write(to: file)

            let oneByteChunks = try SHA256Hasher.hash(fileAt: file, chunkSize: 1)
            let unevenChunks = try SHA256Hasher.hash(fileAt: file, chunkSize: 257)
            let largeChunk = try SHA256Hasher.hash(fileAt: file, chunkSize: 100_000)

            XCTAssertEqual(oneByteChunks, unevenChunks)
            XCTAssertEqual(unevenChunks, largeChunk)
            XCTAssertEqual(oneByteChunks.count, 64)
        }
    }

    func testCancellationIsCheckedAtEachChunk() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("data")
            try Data(repeating: 7, count: 32).write(to: file)
            let checkpointCount = Mutex(0)

            XCTAssertThrowsError(
                try SHA256Hasher.hash(
                    fileAt: file,
                    chunkSize: 8,
                    cancellationCheck: {
                        try checkpointCount.withLock { count in
                            count += 1
                            if count == 3 { throw CancellationError() }
                        }
                    }
                )
            ) { error in
                XCTAssertTrue(error is CancellationError)
            }
            XCTAssertEqual(checkpointCount.withLock { $0 }, 3)
        }
    }

    func testRejectsInvalidChunkSize() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("data")
            try Data().write(to: file)
            XCTAssertThrowsError(try SHA256Hasher.hash(fileAt: file, chunkSize: -1)) { error in
                XCTAssertEqual(error as? SHA256HasherError, .invalidChunkSize(-1))
            }
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SHA256HasherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
