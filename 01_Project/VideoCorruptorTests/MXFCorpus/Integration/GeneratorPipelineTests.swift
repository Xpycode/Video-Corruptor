import Foundation
import XCTest
@testable import VideoCorruptor

final class GeneratorPipelineTests: XCTestCase {
    func testPlaceholderGeneratesDeterministicallyAndPreservesSource() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.mxf")
        try syntheticKLV().write(to: source)
        let original = try Data(contentsOf: source)
        let registry = try MXFFixtureRegistry(fixtures: [PlaceholderFixture()])
        let generator = MXFCorpusGenerator(registry: registry)
        let first = root.appendingPathComponent("corpus-one")
        let second = root.appendingPathComponent("corpus-two")

        let firstReport = try await generator.generate(request(source: source, output: first))
        let secondReport = try await generator.generate(request(source: source, output: second))

        XCTAssertEqual(firstReport.manifest, secondReport.manifest)
        XCTAssertEqual(
            try Data(contentsOf: first.appendingPathComponent("manifest.json")),
            try Data(contentsOf: second.appendingPathComponent("manifest.json"))
        )
        let relativeOutput = try XCTUnwrap(firstReport.manifest.fixtures.first?.output.file.value)
        XCTAssertEqual(
            try Data(contentsOf: first.appendingPathComponent(relativeOutput)),
            try Data(contentsOf: second.appendingPathComponent(relativeOutput))
        )
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(try XCTUnwrap(firstReport.manifest.fixtures.first).output.publicationEligible)
    }

    func testNotApplicableIsReportedWithoutFixtureFile() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.mxf")
        try syntheticKLV().write(to: source)
        let output = root.appendingPathComponent("corpus")
        let generator = MXFCorpusGenerator(
            registry: try MXFFixtureRegistry(fixtures: [NotApplicableFixture()])
        )

        let report = try await generator.generate(request(source: source, output: output))

        XCTAssertTrue(report.manifest.fixtures.isEmpty)
        XCTAssertEqual(report.notApplicable.count, 1)
        XCTAssertEqual(report.notApplicable.first?.reason, "synthetic source lacks requested field")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("manifest.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.appendingPathComponent("fixtures").path), [])
    }

    func testFailureRemovesStagingAndPublishesNothing() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.mxf")
        try syntheticKLV().write(to: source)
        let output = root.appendingPathComponent("corpus")
        let generator = MXFCorpusGenerator(
            registry: try MXFFixtureRegistry(fixtures: [FailingFixture()])
        )

        do {
            _ = try await generator.generate(request(source: source, output: output))
            XCTFail("Expected generation failure")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            try assertNoStaging(in: root, destinationName: "corpus")
        }
    }

    func testCancellationRemovesStaging() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.mxf")
        try syntheticKLV().write(to: source)
        let output = root.appendingPathComponent("corpus")
        let generator = MXFCorpusGenerator(
            registry: try MXFFixtureRegistry(fixtures: [PlaceholderFixture()]),
            cancellationCheck: { checkpoint in
                if checkpoint == .beforeMutation(PlaceholderFixture.id) {
                    throw CancellationError()
                }
            }
        )

        do {
            _ = try await generator.generate(request(source: source, output: output))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            try assertNoStaging(in: root, destinationName: "corpus")
        }
    }

    func testExistingCorpusIsLeftUnchanged() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.mxf")
        try syntheticKLV().write(to: source)
        let output = root.appendingPathComponent("corpus")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let marker = output.appendingPathComponent("marker")
        try Data("keep".utf8).write(to: marker)
        let generator = MXFCorpusGenerator(
            registry: try MXFFixtureRegistry(fixtures: [PlaceholderFixture()])
        )

        do {
            _ = try await generator.generate(request(source: source, output: output))
            XCTFail("Expected existing destination failure")
        } catch {
            XCTAssertEqual(try Data(contentsOf: marker), Data("keep".utf8))
            try assertNoStaging(in: root, destinationName: "corpus")
        }
    }

    private func request(source: URL, output: URL) -> MXFCorpusRequest {
        MXFCorpusRequest(
            sources: [source],
            fixtureIDs: nil,
            outputDirectory: output,
            masterSeed: 42,
            includeSources: true
        )
    }

    private func syntheticKLV() -> Data {
        Data(Array(0..<16) + [0x03, 0xAA, 0xBB, 0xCC])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeneratorPipelineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func assertNoStaging(in root: URL, destinationName: String) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".\(destinationName).staging-") })
    }
}

private struct PlaceholderFixture: MXFFixtureMutation {
    static let id = "mxf.test.placeholder.v1"
    let definition = fixtureDefinition(id: Self.id)

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        guard let element = source.elements.first else {
            return .notApplicable(reason: "no complete KLV")
        }
        return .applicable(targetOffset: element.keySpan.lowerBound, targetClassification: "klv.key")
    }

    func apply(
        to workingFile: URL,
        source: MXFInspectedFile,
        rng: inout SeededRNG
    ) throws -> MXFMutationRecord {
        let offset = source.elements[0].keySpan.lowerBound
        let replacement = UInt8(truncatingIfNeeded: rng.next()) | 0x80
        let edit = try MXFMutationRecorder().recordEdit(
            offset: offset,
            original: Data([0]),
            replacement: Data([replacement]),
            field: "klv.key[0]"
        )
        try MXFEditApplicator().apply(edits: [edit], to: workingFile)
        return MXFMutationRecord(
            targetOffset: MXFDecimalUInt64(offset),
            targetClassification: "klv.key",
            edits: [edit],
            truncation: nil,
            semanticValues: []
        )
    }
}

private struct NotApplicableFixture: MXFFixtureMutation {
    let definition = fixtureDefinition(id: "mxf.test.notApplicable.v1")

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        .notApplicable(reason: "synthetic source lacks requested field")
    }

    func apply(to workingFile: URL, source: MXFInspectedFile, rng: inout SeededRNG) throws -> MXFMutationRecord {
        fatalError("Not-applicable fixtures must not be applied")
    }
}

private struct FailingFixture: MXFFixtureMutation {
    let definition = fixtureDefinition(id: "mxf.test.failure.v1")

    func evaluate(source: MXFInspectedFile) -> MXFFixtureApplicability {
        .applicable(targetOffset: 0, targetClassification: "klv.key")
    }

    func apply(to workingFile: URL, source: MXFInspectedFile, rng: inout SeededRNG) throws -> MXFMutationRecord {
        let edit = try MXFMutationRecorder().recordEdit(
            offset: 0,
            original: Data([0xFF]),
            replacement: Data([0x01])
        )
        try MXFEditApplicator().apply(edits: [edit], to: workingFile)
        fatalError("Applicator must throw")
    }
}

private func fixtureDefinition(id: String) -> MXFFixtureDefinition {
    MXFFixtureDefinition(
        id: id,
        title: "Synthetic fixture",
        rationale: "Exercises the Wave 1 generator shell",
        corpusClass: .parserConformance,
        lifecycle: .draft,
        mutationSchemaVersion: 1,
        requiredSourceCharacteristics: [],
        targetSelectionRule: "first complete KLV",
        parameters: [:],
        seed: nil,
        expectedStructuralCondition: "first key byte differs",
        defaultExpectedResult: MXFExpectedResult(
            outcome: .rejected,
            category: "synthetic",
            consumerCode: nil
        ),
        recommendedLimits: MXFReaderLimits(
            maxInputBytes: MXFDecimalUInt64(1_024),
            maxKLVElements: MXFDecimalUInt64(16),
            maxBERValueLength: MXFDecimalUInt64(1_024),
            maxAllocationBytes: MXFDecimalUInt64(1_024),
            maxLocalSetItems: MXFDecimalUInt64(16),
            maxPartitionHops: MXFDecimalUInt64(16),
            maxVisitedOffsets: MXFDecimalUInt64(16)
        )
    )
}
