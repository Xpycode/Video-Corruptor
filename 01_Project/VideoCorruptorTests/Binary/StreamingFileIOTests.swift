import Foundation
import Synchronization
import XCTest
@testable import VideoCorruptor

final class StreamingFileIOTests: XCTestCase {
    func testCopiesEmptyAndMultiChunkFilesExactly() throws {
        try withTemporaryDirectory { directory in
            let emptySource = directory.appendingPathComponent("empty-source")
            let emptyDestination = directory.appendingPathComponent("empty-copy")
            try Data().write(to: emptySource)

            XCTAssertEqual(
                try StreamingFileIO.copy(from: emptySource, to: emptyDestination, chunkSize: 3),
                0
            )
            XCTAssertEqual(try Data(contentsOf: emptyDestination), Data())

            let source = directory.appendingPathComponent("source")
            let destination = directory.appendingPathComponent("copy")
            let bytes = Data((0..<10_003).map { UInt8($0 % 251) })
            try bytes.write(to: source)

            XCTAssertEqual(
                try StreamingFileIO.copy(from: source, to: destination, chunkSize: 127),
                UInt64(bytes.count)
            )
            XCTAssertEqual(try Data(contentsOf: destination), bytes)
        }
    }

    func testCancellationAfterAChunkRemovesIncompleteDestination() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("source")
            let destination = directory.appendingPathComponent("copy")
            let original = Data(repeating: 0xA5, count: 32)
            try original.write(to: source)
            let checkpointCount = Mutex(0)

            XCTAssertThrowsError(
                try StreamingFileIO.copy(
                    from: source,
                    to: destination,
                    chunkSize: 8,
                    cancellationCheck: {
                        try checkpointCount.withLock { count in
                            count += 1
                            if count == 2 { throw CancellationError() }
                        }
                    }
                )
            ) { error in
                XCTAssertTrue(error is CancellationError)
            }

            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(checkpointCount.withLock { $0 }, 2)
        }
    }

    func testRejectsInvalidChunkSizeSameFileAndExistingDestination() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("source")
            let destination = directory.appendingPathComponent("destination")
            try Data([1]).write(to: source)

            XCTAssertThrowsError(
                try StreamingFileIO.copy(from: source, to: destination, chunkSize: 0)
            ) { error in
                XCTAssertEqual(error as? StreamingFileIOError, .invalidChunkSize(0))
            }
            XCTAssertThrowsError(try StreamingFileIO.copy(from: source, to: source)) { error in
                XCTAssertEqual(error as? StreamingFileIOError, .sourceAndDestinationAreSame)
            }

            try Data([2]).write(to: destination)
            XCTAssertThrowsError(try StreamingFileIO.copy(from: source, to: destination)) { error in
                XCTAssertEqual(error as? StreamingFileIOError, .destinationAlreadyExists)
            }
            XCTAssertEqual(try Data(contentsOf: destination), Data([2]))
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamingFileIOTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
