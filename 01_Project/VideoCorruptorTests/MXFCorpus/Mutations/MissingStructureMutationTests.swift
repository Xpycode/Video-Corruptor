import Foundation
import XCTest
@testable import VideoCorruptor

final class MissingStructureMutationTests: XCTestCase {
    func testUndeclaredSemanticFixturesAreNotApplicable() {
        let source = MXFStructuralInspector().inspect(data: header + footer)
        for fixture in MXFMissingStructureMutations.undeclared {
            guard case .notApplicable(let reason) = fixture.evaluate(source: source) else {
                return XCTFail("Undeclared \(fixture.kind) must not apply")
            }
            XCTAssertTrue(reason.contains("declaration"))
            XCTAssertEqual(fixture.definition.parameters["profile"], "undeclared")
            XCTAssertNil(fixture.definition.defaultExpectedResult.consumerCode)
            XCTAssertEqual(fixture.definition.lifecycle, .draft)
        }
    }

    func testOP1aAndOPAtomPoliciesAreExplicitlyDifferentForFooter() throws {
        let op1a = try XCTUnwrap(MXFMissingStructureMutations.fixtures(sourceDeclaration: .op1a)
            .first { $0.kind == .footerPartition })
        let atom = try XCTUnwrap(MXFMissingStructureMutations.fixtures(sourceDeclaration: .opAtom)
            .first { $0.kind == .footerPartition })
        XCTAssertEqual(op1a.definition.parameters["profile"], "OP1a")
        XCTAssertEqual(op1a.definition.defaultExpectedResult,
                       .init(outcome: .rejected, category: "missingFooter", consumerCode: nil))
        XCTAssertEqual(atom.definition.parameters["profile"], "OP-Atom")
        XCTAssertEqual(atom.definition.defaultExpectedResult,
                       .init(outcome: .acceptedWithWarning, category: "missingFooterFallback", consumerCode: nil))
    }

    func testHeaderKeyEditIsExactAndReinspectionFindsNoHeader() throws {
        let data = header + body
        let inspected = MXFStructuralInspector().inspect(data: data)
        let fixture = try XCTUnwrap(MXFMissingStructureMutations.fixtures(sourceDeclaration: .op1a)
            .first { $0.kind == .headerPartition })
        let sourceURL = try temporaryFile(data)
        let outputURL = try temporaryFile(data)
        defer { cleanup(sourceURL, outputURL) }
        var rng = SeededRNG(seed: 9)
        let record = try fixture.apply(to: outputURL, source: inspected, rng: &rng)
        XCTAssertEqual(record.edits.count, 1)
        XCTAssertEqual(record.edits[0].offset.value, 13)
        XCTAssertEqual(record.edits[0].field, "headerPartitionKeyKind")
        try MXFCorpusVerifier().verify(sourceURL: sourceURL, outputURL: outputURL,
                                       edits: record.edits,
                                       postconditions: fixture.postconditions(for: inspected))
    }

    func testFooterAndRIPAreExactPrefixTruncations() throws {
        let cases: [(MXFMissingStructureKind, Data, UInt64)] = [
            (.footerPartition, header + footer, UInt64(header.count)),
            (.rip, header + rip, UInt64(header.count))
        ]
        for (kind, data, retained) in cases {
            let inspected = MXFStructuralInspector().inspect(data: data)
            let fixture = try XCTUnwrap(MXFMissingStructureMutations.fixtures(sourceDeclaration: .opAtom)
                .first { $0.kind == kind })
            let sourceURL = try temporaryFile(data)
            let outputURL = try temporaryFile(data)
            defer { cleanup(sourceURL, outputURL) }
            XCTAssertEqual(fixture.evaluate(source: inspected),
                           .applicable(targetOffset: retained,
                                       targetClassification: kind == .rip
                                        ? "random index pack and trailing bytes"
                                        : "footer partition and trailing bytes"))
            var rng = SeededRNG(seed: 3)
            let record = try fixture.apply(to: outputURL, source: inspected, rng: &rng)
            XCTAssertTrue(record.edits.isEmpty)
            XCTAssertEqual(record.truncation?.retainedSize.value, retained)
            try MXFCorpusVerifier(chunkSize: 11).verify(
                sourceURL: sourceURL, outputURL: outputURL, edits: [],
                truncation: record.truncation, postconditions: fixture.postconditions(for: inspected)
            )
            XCTAssertEqual(Data(data.prefix(Int(retained))), try Data(contentsOf: outputURL))
        }
    }

    private var header: Data { partition(kind: 0x02) }
    private var body: Data { partition(kind: 0x03) }
    private var footer: Data { partition(kind: 0x04) }
    private var rip: Data {
        Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
              0x0d, 0x01, 0x02, 0x01, 0x01, 0x11, 0x01, 0x00]) + Data([0x00])
    }
    private func partition(kind: UInt8) -> Data {
        Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
              0x0d, 0x01, 0x02, 0x01, 0x01, kind, 0x04, 0x00])
            + Data([88]) + Data(repeating: 0, count: 88)
    }
    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-structure-\(UUID().uuidString).mxf")
        try data.write(to: url)
        return url
    }
    private func cleanup(_ urls: URL...) { for url in urls { try? FileManager.default.removeItem(at: url) } }
}
