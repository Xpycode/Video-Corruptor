import Foundation
import XCTest
@testable import VideoCorruptor

final class MutationTransactionTests: XCTestCase {
    func testApplicatorSortsEditsAndVerifierAcceptsExactDiff() throws {
        let source = try temporaryFile(bytes: [0, 1, 2, 3, 4, 5])
        let output = try temporaryFile(bytes: [0, 1, 2, 3, 4, 5])
        let recorder = MXFMutationRecorder()
        let edits = [
            try recorder.recordEdit(offset: 4, original: Data([4]), replacement: Data([40])),
            try recorder.recordEdit(offset: 1, original: Data([1, 2]), replacement: Data([10, 20])),
        ]

        try MXFEditApplicator().apply(edits: edits, to: output)
        XCTAssertEqual(try Data(contentsOf: output), Data([0, 10, 20, 3, 40, 5]))
        try MXFCorpusVerifier(chunkSize: 2).verify(
            sourceURL: source,
            outputURL: output,
            edits: edits
        )
    }

    func testApplicatorChecksEveryOriginalBeforeWriting() throws {
        let output = try temporaryFile(bytes: [0, 1, 2, 3])
        let recorder = MXFMutationRecorder()
        let edits = [
            try recorder.recordEdit(offset: 0, original: Data([0]), replacement: Data([9])),
            try recorder.recordEdit(offset: 2, original: Data([8]), replacement: Data([7])),
        ]

        XCTAssertThrowsError(try MXFEditApplicator().apply(edits: edits, to: output)) { error in
            XCTAssertEqual(error as? MXFMutationTransactionError, .originalByteMismatch(offset: 2))
        }
        XCTAssertEqual(try Data(contentsOf: output), Data([0, 1, 2, 3]))
    }

    func testRecorderRejectsUnequalAndOverlappingEdits() throws {
        let recorder = MXFMutationRecorder()
        XCTAssertThrowsError(
            try recorder.recordEdit(offset: 0, original: Data([0]), replacement: Data([1, 2]))
        )
        let edits = [
            try recorder.recordEdit(offset: 1, original: Data([1, 2]), replacement: Data([8, 8])),
            try recorder.recordEdit(offset: 2, original: Data([2]), replacement: Data([7])),
        ]
        XCTAssertThrowsError(try recorder.validateAndSort(edits: edits)) { error in
            guard case .overlappingEdits = error as? MXFMutationTransactionError else {
                return XCTFail("Expected overlap, got \(error)")
            }
        }
    }

    func testVerifierRejectsUndeclaredChangeAndByteIdenticalOutput() throws {
        let source = try temporaryFile(bytes: [0, 1, 2])
        let changed = try temporaryFile(bytes: [0, 9, 2])
        XCTAssertThrowsError(
            try MXFCorpusVerifier(chunkSize: 1).verify(sourceURL: source, outputURL: changed, edits: [])
        ) { error in
            XCTAssertEqual(error as? MXFMutationTransactionError, .undeclaredChange(offset: 1))
        }

        let identical = try temporaryFile(bytes: [0, 1, 2])
        XCTAssertThrowsError(
            try MXFCorpusVerifier().verify(sourceURL: source, outputURL: identical, edits: [])
        ) { error in
            XCTAssertEqual(error as? MXFMutationTransactionError, .byteIdenticalOutput)
        }
    }

    func testVerifierRejectsReplacementMismatch() throws {
        let source = try temporaryFile(bytes: [0, 1, 2])
        let output = try temporaryFile(bytes: [0, 8, 2])
        let edit = try MXFMutationRecorder().recordEdit(
            offset: 1,
            original: Data([1]),
            replacement: Data([9])
        )
        XCTAssertThrowsError(
            try MXFCorpusVerifier().verify(sourceURL: source, outputURL: output, edits: [edit])
        ) { error in
            XCTAssertEqual(error as? MXFMutationTransactionError, .replacementByteMismatch(offset: 1))
        }
    }

    func testTruncationRequiresExactUnchangedPrefix() throws {
        let source = try temporaryFile(bytes: [0, 1, 2, 3, 4])
        let valid = try temporaryFile(bytes: [0, 1, 2])
        let truncation = try MXFTruncationRecord(
            originalSize: 5,
            retainedSize: 3,
            containingElement: "body",
            boundary: "inside value"
        )
        try MXFCorpusVerifier(chunkSize: 2).verify(
            sourceURL: source,
            outputURL: valid,
            edits: [],
            truncation: truncation
        )

        let invalid = try temporaryFile(bytes: [0, 9, 2])
        XCTAssertThrowsError(
            try MXFCorpusVerifier().verify(
                sourceURL: source,
                outputURL: invalid,
                edits: [],
                truncation: truncation
            )
        ) { error in
            XCTAssertEqual(error as? MXFMutationTransactionError, .incorrectTruncationPrefix(offset: 1))
        }
    }

    func testApplicatorPerformsExplicitTruncationAndHookRuns() throws {
        let source = try temporaryFile(bytes: [0, 1, 2, 3])
        let output = try temporaryFile(bytes: [0, 1, 2, 3])
        let truncation = try MXFTruncationRecord(
            originalSize: 4,
            retainedSize: 2,
            containingElement: nil,
            boundary: "element boundary"
        )
        try MXFEditApplicator().apply(edits: [], truncation: truncation, to: output)
        try MXFCorpusVerifier().verify(
            sourceURL: source,
            outputURL: output,
            edits: [],
            truncation: truncation,
            postconditions: [{ context in
                guard context.truncation?.retainedSize.value == 2 else {
                    throw HookError.failed
                }
            }]
        )
        XCTAssertEqual(try Data(contentsOf: output), Data([0, 1]))
    }

    private enum HookError: Error { case failed }

    private func temporaryFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MutationTransactionTests-\(UUID().uuidString)")
        try Data(bytes).write(to: url, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
