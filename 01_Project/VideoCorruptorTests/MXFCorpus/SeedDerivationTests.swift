import XCTest
@testable import VideoCorruptor

final class SeedDerivationTests: XCTestCase {
    func testEveryExistingCorruptionTypeRetainsItsGoldenStream() {
        let master: UInt64 = 0x0123456789ABCDEF
        let expectedFirstValues: [CorruptionType: UInt64] = [
            .truncation: 0x5256A07B65AD1C11,
            .zeroByteFile: 0x2B355DE7944BC4B0,
            .fakeExtension: 0x88CC38BF61A08E24,
            .corruptHeader: 0x3B0F5935012CB2AE,
            .timestampGap: 0x30ECB1269BC93897,
            .decodeError: 0xBF369DE8B22C9D72,
            .missingVideoTrack: 0xFFCF5E79706D2F1B,
            .missingAudioTrack: 0x0E380AEFE4988550,
            .containerStructure: 0xBC6E0BD39B03CCB9,
            .chunkOffsetShift: 0xCC0C32DF52D47867,
            .keyframeRemoval: 0x8B973BEBE585B6D5,
            .sampleSizeCorruption: 0x5E398D9AA660218D,
            .iFrameDatamosh: 0xB7B1710FAA108388,
            .targetedFrameCorruption: 0xBDF1A1F1FF24AA04,
            .mxfEssenceCorruption: 0x80BFBF319A3764B6,
            .mxfKLVKeyCorruption: 0xAC23425E5CB149E4,
            .mxfBERLengthManipulation: 0x3B6DF933F9CA6DFA,
            .mxfPartitionBreakage: 0x00E03510F266A7B4,
            .mxfIndexScrambling: 0xC03D238936012A40,
        ]

        XCTAssertEqual(expectedFirstValues.count, CorruptionType.allCases.count)
        for type in CorruptionType.allCases {
            var rng = SeedDerivation.rng(master: master, for: type)
            XCTAssertEqual(rng.next(), expectedFirstValues[type], "Golden changed for \(type.rawValue)")
        }
    }

    func testExistingTypeSequenceGoldensCoverBoundaryMasterSeeds() {
        assertSequence(
            master: 0,
            type: .truncation,
            expected: [
                0x5186DAA68729668E,
                0xA4BEE8B0B595447C,
                0xC3C1EAFF6F3C957A,
                0x59DF2E695342CDA6,
            ]
        )
        assertSequence(
            master: 42,
            type: .mxfBERLengthManipulation,
            expected: [
                0x872D9515B1540FA9,
                0x49EB4C79F42C2AA9,
                0xC383BB07DD0E10D2,
                0x72F9B01EF0910587,
            ]
        )
        assertSequence(
            master: UInt64.max,
            type: .targetedFrameCorruption,
            expected: [
                0x66F26A15B4CD0356,
                0x29A910368F2B025E,
                0xC1DA1B2659142AE7,
                0x07AEF5F9C540A5FA,
            ]
        )
    }

    func testFixtureKeyHasStableGoldenSequence() {
        var rng = SeedDerivation.rng(
            master: 0x0123456789ABCDEF,
            key: "mxf.ber.indefiniteForm.v1"
        )

        XCTAssertEqual(
            (0..<4).map { _ in rng.next() },
            [
                0xF18C31479364D462,
                0x033367D1E5EDCAEB,
                0x16D8C63C0FCABFD8,
                0x0AE53484DB9D41E9,
            ]
        )
    }

    func testFixtureStreamDoesNotDependOnRegistryInsertionOrRemoval() {
        let master: UInt64 = 0xDEADBEEFCAFEBABE
        let target = "mxf.partition.previousSelfCycle.v1"
        let originalRegistry = [
            "mxf.ber.indefiniteForm.v1",
            target,
            "mxf.count.batchExceedsPayload.v1",
        ]
        let registryWithInsertion = [
            "mxf.missing.headerPartition.v1",
            "mxf.ber.indefiniteForm.v1",
            target,
            "mxf.count.batchExceedsPayload.v1",
            "mxf.missing.rip.v1",
        ]
        let registryAfterRemoval = [target]

        let original = outputs(for: originalRegistry, master: master)[target]
        let afterInsertion = outputs(for: registryWithInsertion, master: master)[target]
        let afterRemoval = outputs(for: registryAfterRemoval, master: master)[target]

        XCTAssertEqual(original, afterInsertion)
        XCTAssertEqual(original, afterRemoval)
    }

    func testFixtureIDsReceiveIndependentStreams() {
        let master: UInt64 = 1234
        var first = SeedDerivation.rng(master: master, key: "mxf.ber.indefiniteForm.v1")
        var second = SeedDerivation.rng(master: master, key: "mxf.ber.valueBeyondEOF.v1")

        XCTAssertNotEqual(first.next(), second.next())
    }

    private func assertSequence(
        master: UInt64,
        type: CorruptionType,
        expected: [UInt64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var rng = SeedDerivation.rng(master: master, for: type)
        XCTAssertEqual(
            expected.map { _ in rng.next() },
            expected,
            file: file,
            line: line
        )
    }

    private func outputs(for registry: [String], master: UInt64) -> [String: [UInt64]] {
        Dictionary(uniqueKeysWithValues: registry.map { fixtureID in
            var rng = SeedDerivation.rng(master: master, key: fixtureID)
            return (fixtureID, (0..<8).map { _ in rng.next() })
        })
    }
}
