import Foundation
import XCTest
@testable import VideoCorruptor

final class CorpusReleaseTests: XCTestCase {
    /// Narrow export seam for publishing the deterministic, project-owned release into a consumer
    /// repository. The destination is supplied by the caller and is never encoded in corpus data.
    func testExportControlledReleaseWhenRequested() async throws {
        guard let destination = ProcessInfo.processInfo.environment["VIDEO_CORRUPTOR_CORPUS_EXPORT"],
              !destination.isEmpty else { throw XCTSkip("Set VIDEO_CORRUPTOR_CORPUS_EXPORT to export") }
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("controlled-op1a.mxf")
        try SyntheticMXFBuilder.make(.op1a).write(to: source)
        let registry = try MXFFixtureRegistry.complete(declarations: .init(missingStructures: .op1a))
        let generator = MXFCorpusGenerator(
            registry: registry,
            sourceProfile: SyntheticMXFProfile.op1a.rawValue,
            sourceRights: SyntheticMXFSourceKit.source(for: .op1a).sourceRights
        )
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        let report = try await generator.generate(request(source: source, output: output))
        XCTAssertEqual(report.manifest.fixtures.count, 19)
        XCTAssertEqual(report.notApplicable.count, 26)
    }

    /// Wave 5 intentionally releases only the structurally applicable portion of the controlled
    /// OP1a source. The other required IDs remain visible as explicit notApplicable results until
    /// richer, offset-bearing source declarations exist.
    func testControlledReleaseIsByteIdenticalAcrossTwoGenerations() async throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("controlled-op1a.mxf")
        let original = SyntheticMXFBuilder.make(.op1a)
        try original.write(to: source)

        let registry = try MXFFixtureRegistry.complete(
            declarations: .init(missingStructures: .op1a)
        )
        let generator = MXFCorpusGenerator(
            registry: registry,
            sourceProfile: SyntheticMXFProfile.op1a.rawValue,
            sourceRights: SyntheticMXFSourceKit.source(for: .op1a).sourceRights
        )
        let firstRoot = root.appendingPathComponent("release-one")
        let secondRoot = root.appendingPathComponent("release-two")
        let first = try await generator.generate(request(source: source, output: firstRoot))
        let second = try await generator.generate(request(source: source, output: secondRoot))

        XCTAssertEqual(first.manifest.fixtures.count, 19)
        XCTAssertEqual(first.notApplicable.count, 26)
        XCTAssertEqual(Set(first.manifest.fixtures.map(\.id)).count, 19)
        XCTAssertEqual(
            Set(first.manifest.fixtures.map(\.id)).union(first.notApplicable.map(\.fixtureID)),
            MXFFixtureRegistry.requiredFixtureIDs
        )
        XCTAssertTrue(first.notApplicable.allSatisfy {
            !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        XCTAssertTrue(first.manifest.fixtures.allSatisfy {
            $0.lifecycle == .structurallyVerified && $0.expected.consumerCode == nil
        })
        XCTAssertFalse(first.manifest.fixtures.contains { $0.lifecycle == .approved })

        XCTAssertEqual(first.manifest, second.manifest)
        XCTAssertEqual(first.notApplicable, second.notApplicable)
        XCTAssertEqual(try treePaths(firstRoot), try treePaths(secondRoot))
        XCTAssertEqual(
            try Data(contentsOf: firstRoot.appendingPathComponent("manifest.json")),
            try Data(contentsOf: secondRoot.appendingPathComponent("manifest.json"))
        )
        try validateRelease(first, at: firstRoot)
        try validateRelease(second, at: secondRoot)
        XCTAssertEqual(try Data(contentsOf: source), original, "generation must not mutate its source")
    }

    func testLifecycleCannotSkipStructuralVerificationOrConsumerMapping() throws {
        XCTAssertNoThrow(try MXFFixtureLifecycleTransition.validate(
            from: .generated, to: .structurallyVerified, consumerCode: nil
        ))
        XCTAssertThrowsError(try MXFFixtureLifecycleTransition.validate(
            from: .generated, to: .approved, consumerCode: "mxf.ok"
        ))
        XCTAssertThrowsError(try MXFFixtureLifecycleTransition.validate(
            from: .structurallyVerified, to: .approved, consumerCode: "mxf.ok"
        ))
        XCTAssertThrowsError(try MXFFixtureLifecycleTransition.validate(
            from: .structurallyVerified, to: .consumerMapped, consumerCode: nil
        )) { error in
            XCTAssertEqual(error as? MXFFixtureLifecycleTransitionError,
                           .missingConsumerCode(stage: .consumerMapped))
        }
        XCTAssertThrowsError(try MXFFixtureLifecycleTransition.validate(
            from: .consumerMapped, to: .approved, consumerCode: "  "
        )) { error in
            XCTAssertEqual(error as? MXFFixtureLifecycleTransitionError,
                           .missingConsumerCode(stage: .approved))
        }
        XCTAssertNoThrow(try MXFFixtureLifecycleTransition.validate(
            from: .consumerMapped, to: .approved, consumerCode: "mxf.bounded-reader.result"
        ))
    }

    private func validateRelease(_ report: MXFCorpusReport, at root: URL) throws {
        try MXFManifestValidator().validate(report.manifest, corpusRoot: root)
        let expectedPaths = Set(
            ["fixtures", "manifest.json", "sources"] +
            report.manifest.fixtures.map(\.output.file.value) +
            report.manifest.fixtures.map(\.source.file.value)
        )
        XCTAssertEqual(try treePaths(root), expectedPaths)

        for fixture in report.manifest.fixtures {
            let source = root.appendingPathComponent(fixture.source.file.value)
            let output = root.appendingPathComponent(fixture.output.file.value)
            let sourceBytes = try Data(contentsOf: source)
            let outputBytes = try Data(contentsOf: output)
            XCTAssertEqual(UInt64(sourceBytes.count), fixture.source.size.value, fixture.id)
            XCTAssertEqual(UInt64(outputBytes.count), fixture.output.size.value, fixture.id)
            XCTAssertEqual(try SHA256Hasher.hash(fileAt: source), fixture.source.sha256, fixture.id)
            XCTAssertEqual(try SHA256Hasher.hash(fileAt: output), fixture.output.sha256, fixture.id)
            XCTAssertNotEqual(fixture.source.sha256, fixture.output.sha256, fixture.id)
            XCTAssertFalse(fixture.mutation.edits.isEmpty && fixture.mutation.truncation == nil, fixture.id)
            for edit in fixture.mutation.edits {
                let offset = Int(edit.offset.value)
                let original = try XCTUnwrap(Data(hex: edit.originalHex.value))
                let replacement = try XCTUnwrap(Data(hex: edit.replacementHex.value))
                XCTAssertEqual(Data(sourceBytes[offset..<(offset + original.count)]), original, fixture.id)
                XCTAssertEqual(Data(outputBytes[offset..<(offset + replacement.count)]), replacement, fixture.id)
            }
            if let truncation = fixture.mutation.truncation {
                XCTAssertEqual(truncation.originalSize.value, UInt64(sourceBytes.count), fixture.id)
                XCTAssertEqual(truncation.retainedSize.value, UInt64(outputBytes.count), fixture.id)
                XCTAssertEqual(outputBytes, sourceBytes.prefix(outputBytes.count), fixture.id)
            }
        }
    }

    private func request(source: URL, output: URL) -> MXFCorpusRequest {
        MXFCorpusRequest(sources: [source], fixtureIDs: nil, outputDirectory: output,
                         masterSeed: 0x5eed, includeSources: true)
    }

    private func treePaths(_ root: URL) throws -> Set<String> {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: resolvedRoot, includingPropertiesForKeys: keys, options: [], errorHandler: nil
        ))
        var paths = Set<String>()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            XCTAssertFalse(values.isSymbolicLink == true)
            let components = url.standardizedFileURL.pathComponents
                .dropFirst(resolvedRoot.pathComponents.count)
            paths.insert(components.joined(separator: "/"))
        }
        return paths
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorpusReleaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            append(byte)
            index = next
        }
    }
}
