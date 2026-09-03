import XCTest
@testable import VideoCorruptor

final class SyntheticMXFSourceKitTests: XCTestCase {
    func testBuilderIsDeterministicAndCheckedInBytesAreExact() throws {
        for source in SyntheticMXFSourceKit.sources {
            let first = SyntheticMXFBuilder.make(source.profile)
            XCTAssertEqual(first, SyntheticMXFBuilder.make(source.profile))
            XCTAssertEqual(first, try fixtureBytes(source.fixtureName))
            XCTAssertEqual(SyntheticMXFBuilder.sha256(first), source.sha256)
        }
    }

    func testProfilesHaveDistinctOperationalPatternsAndEssenceLayouts() throws {
        let op1a = SyntheticMXFBuilder.make(.op1a)
        let atom = SyntheticMXFBuilder.make(.opAtom)
        XCTAssertNotEqual(op1a, atom)

        let inspector = MXFStructuralInspector()
        let op1aFile = inspector.inspect(data: op1a)
        let atomFile = inspector.inspect(data: atom)
        XCTAssertTrue(op1aFile.completedWalk)
        XCTAssertTrue(atomFile.completedWalk)
        XCTAssertEqual(op1aFile.elements.count, 5) // header, body, two essence KLVs, footer
        XCTAssertEqual(atomFile.elements.count, 4) // header, body, one essence KLV, footer

        let partitionInspector = MXFPartitionInspector()
        let op1aHeader = try XCTUnwrap(partitionPack(op1aFile.elements[0], bytes: op1a,
                                                     inspector: partitionInspector))
        let atomHeader = try XCTUnwrap(partitionPack(atomFile.elements[0], bytes: atom,
                                                     inspector: partitionInspector))
        XCTAssertNotEqual(op1aHeader.operationalPattern.value, atomHeader.operationalPattern.value)
        XCTAssertEqual(op1aHeader.operationalPattern.value[12], 0x01)
        XCTAssertEqual(atomHeader.operationalPattern.value[12], 0x10)
    }

    func testPartitionLinksAreSelfConsistentAndProfileTagged() throws {
        for source in SyntheticMXFSourceKit.sources {
            let bytes = SyntheticMXFBuilder.make(source.profile)
            let inspected = MXFStructuralInspector().inspect(data: bytes)
            let partitionElements = inspected.elements.filter {
                MXFPartitionInspector().classify(key: $0.key) != nil
            }
            XCTAssertEqual(partitionElements.count, 3)

            for element in partitionElements {
                let pack = try XCTUnwrap(partitionPack(
                    element, bytes: bytes, inspector: MXFPartitionInspector()
                ))
                XCTAssertEqual(pack.thisPartition.value, element.keySpan.lowerBound)
                XCTAssertEqual(pack.footerPartition.value,
                               partitionElements.last?.keySpan.lowerBound)
            }
            let identity = try source.sourceIdentity(size: UInt64(bytes.count))
            XCTAssertEqual(identity.profile, source.profile.rawValue)
            XCTAssertEqual(identity.sha256, source.sha256)
        }
    }

    func testRightsAndProvenancePropagateWithoutBroadening() throws {
        for source in SyntheticMXFSourceKit.sources {
            XCTAssertTrue(source.provenance.contains("no third-party media"))
            XCTAssertTrue(source.repositoryAllowed)
            XCTAssertEqual(source.rightsDisposition, .projectOwnedCC0)
            XCTAssertTrue(source.sourceRights.redistributable)
            XCTAssertEqual(source.sourceRights.repositoryEligible, source.repositoryAllowed)
            XCTAssertTrue(source.sourceRights.permitsPublication)
            XCTAssertEqual(source.sourceRights.licenseIdentifier, "CC0-1.0")
        }

        let restricted = SyntheticMXFSource(
            fixtureName: "external.mxf", profile: .op1a,
            sha256: String(repeating: "0", count: 64), provenance: "external test source",
            repositoryAllowed: false, rightsDisposition: .externalRestricted,
            licenseIdentifier: nil
        )
        XCTAssertFalse(restricted.sourceRights.redistributable)
        XCTAssertFalse(restricted.sourceRights.repositoryEligible)
        XCTAssertFalse(restricted.sourceRights.permitsPublication)
    }

    private func fixtureBytes(_ name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: parts[0], withExtension: parts[1])
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        return try XCTUnwrap(SyntheticMXFBuilder.decodeHexFixture(text))
    }

    private func partitionPack(
        _ element: MXFInspectedElement,
        bytes: Data,
        inspector: MXFPartitionInspector
    ) -> MXFPartitionPackInspection? {
        guard case .partitionPack(let pack) = inspector.inspect(element: element, in: bytes) else {
            return nil
        }
        return pack
    }
}
