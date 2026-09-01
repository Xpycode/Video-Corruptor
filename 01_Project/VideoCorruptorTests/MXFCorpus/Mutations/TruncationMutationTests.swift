import Foundation
import XCTest
@testable import VideoCorruptor

final class TruncationMutationTests: XCTestCase {
    func testDefinitionsHaveStableIDsAndPolicyAppropriateExpectedResults() throws {
        XCTAssertEqual(MXFTruncationMutations.all.map(\.definition.id), [
            "mxf.truncation.insideKey.v1",
            "mxf.truncation.immediatelyPostKey.v1",
            "mxf.truncation.insideLongBER.v1",
            "mxf.truncation.immediatelyPostLongBER.v1",
            "mxf.truncation.oneByteBeforeValueEnd.v1",
            "mxf.truncation.betweenCompleteKLVTriplets.v1"
        ])
        XCTAssertTrue(MXFTruncationMutations.all.allSatisfy {
            $0.definition.lifecycle == .draft
                && $0.definition.defaultExpectedResult.consumerCode == nil
        })

        for mutation in MXFTruncationMutations.all.dropLast() {
            XCTAssertEqual(mutation.definition.defaultExpectedResult.outcome, .rejected)
            XCTAssertEqual(mutation.definition.defaultExpectedResult.category, "unexpectedEOF")
        }
        let cleanEnd = try XCTUnwrap(MXFTruncationMutations.all.last)
        XCTAssertEqual(cleanEnd.definition.defaultExpectedResult.outcome, .acceptedWithWarning)
        XCTAssertEqual(cleanEnd.definition.defaultExpectedResult.category, "cleanEndBeforeRemainingKLVs")
    }

    func testEveryRetainedSizeIsDerivedFromInspectedStructure() throws {
        let sourceData = syntheticSource()
        let inspected = MXFStructuralInspector().inspect(data: sourceData)
        XCTAssertTrue(inspected.completedWalk)
        XCTAssertEqual(inspected.elements.count, 2)

        let expected: [MXFGenericTruncationKind: UInt64] = [
            .insideKey: inspected.elements[0].keySpan.lowerBound + 8,
            .immediatelyPostKey: inspected.elements[0].keySpan.upperBound,
            .insideLongBER: inspected.elements[0].ber.physicalSpan.lowerBound + 1,
            .immediatelyPostLongBER: inspected.elements[0].ber.physicalSpan.upperBound,
            .oneByteBeforeValueEnd: try XCTUnwrap(inspected.elements[0].valueSpan).upperBound - 1,
            .betweenCompleteKLVTriplets: inspected.elements[0].physicalSpan.upperBound
        ]

        for mutation in MXFTruncationMutations.all {
            let targetSize = try XCTUnwrap(expected[mutation.kind])
            XCTAssertEqual(
                mutation.evaluate(source: inspected),
                .applicable(
                    targetOffset: 0,
                    targetClassification: classification(for: mutation.kind)
                )
            )

            let sourceURL = try temporaryFile(contents: sourceData)
            let outputURL = try temporaryFile(contents: sourceData)
            defer {
                try? FileManager.default.removeItem(at: sourceURL)
                try? FileManager.default.removeItem(at: outputURL)
            }
            var rng = SeededRNG(seed: 7)
            let record = try mutation.apply(to: outputURL, source: inspected, rng: &rng)
            XCTAssertTrue(record.edits.isEmpty)
            XCTAssertEqual(record.truncation?.originalSize.value, UInt64(sourceData.count))
            XCTAssertEqual(record.truncation?.retainedSize.value, targetSize)
            XCTAssertFalse(record.truncation?.boundary.isEmpty ?? true)
            XCTAssertEqual(record.truncation?.containingElement, "KLV at byte 0")

            try MXFCorpusVerifier(chunkSize: 7).verify(
                sourceURL: sourceURL,
                outputURL: outputURL,
                edits: record.edits,
                truncation: record.truncation
            )
            XCTAssertEqual(try fileSize(outputURL), targetSize)
        }
    }

    func testExactVerifierRejectsAChangedByteInTruncatedPrefix() throws {
        let sourceData = syntheticSource()
        let inspected = MXFStructuralInspector().inspect(data: sourceData)
        let mutation = MXFGenericTruncationMutation(kind: .betweenCompleteKLVTriplets)
        let sourceURL = try temporaryFile(contents: sourceData)
        let outputURL = try temporaryFile(contents: sourceData)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        var rng = SeededRNG(seed: 1)
        let record = try mutation.apply(to: outputURL, source: inspected, rng: &rng)

        let handle = try FileHandle(forUpdating: outputURL)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data([0xff]))
        try handle.close()

        XCTAssertThrowsError(try MXFCorpusVerifier().verify(
            sourceURL: sourceURL,
            outputURL: outputURL,
            edits: [],
            truncation: record.truncation
        )) { error in
            XCTAssertEqual(error as? MXFMutationTransactionError, .incorrectTruncationPrefix(offset: 0))
        }
    }

    func testMissingBoundariesAreNotApplicable() {
        let empty = MXFStructuralInspector().inspect(data: Data())
        for mutation in MXFTruncationMutations.all {
            guard case .notApplicable(let reason) = mutation.evaluate(source: empty) else {
                return XCTFail("Expected \(mutation.kind) to be not applicable")
            }
            XCTAssertTrue(reason.contains("Source lacks required boundary"))
        }

        let shortBEROnly = MXFStructuralInspector().inspect(
            data: Data(repeating: 0x33, count: 16) + Data([0x00])
        )
        for kind in [MXFGenericTruncationKind.insideLongBER, .immediatelyPostLongBER,
                     .oneByteBeforeValueEnd, .betweenCompleteKLVTriplets] {
            let mutation = MXFGenericTruncationMutation(kind: kind)
            guard case .notApplicable = mutation.evaluate(source: shortBEROnly) else {
                return XCTFail("Expected absent \(kind) boundary to be not applicable")
            }
        }
    }

    private func syntheticSource() -> Data {
        let first = Data(repeating: 0x11, count: 16)
            + Data([0x82, 0x00, 0x80])
            + Data(repeating: 0xaa, count: 128)
        let second = Data(repeating: 0x22, count: 16) + Data([0x00])
        return first + second
    }

    private func classification(for kind: MXFGenericTruncationKind) -> String {
        switch kind {
        case .insideKey: "KLV key"
        case .immediatelyPostKey: "post-KLV key"
        case .insideLongBER: "long-form BER"
        case .immediatelyPostLongBER: "post-long-form BER"
        case .oneByteBeforeValueEnd: "KLV value"
        case .betweenCompleteKLVTriplets: "complete KLV triplet boundary"
        }
    }

    private func temporaryFile(contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truncation-\(UUID().uuidString).mxf")
        try contents.write(to: url)
        return url
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.size] as? NSNumber)?.uint64Value)
    }
}
