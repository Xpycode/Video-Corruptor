import CryptoKit
import Foundation
@testable import VideoCorruptor

enum SyntheticMXFProfile: String, CaseIterable, Sendable {
    case op1a = "OP1a"
    case opAtom = "OP-Atom"
}

enum SyntheticMXFRightsDisposition: String, Sendable {
    case projectOwnedCC0 = "project-owned-cc0"
    case externalRestricted = "external-restricted"
}

struct SyntheticMXFSource: Equatable, Sendable {
    let fixtureName: String
    let profile: SyntheticMXFProfile
    let sha256: String
    let provenance: String
    let repositoryAllowed: Bool
    let rightsDisposition: SyntheticMXFRightsDisposition
    let licenseIdentifier: String?

    var sourceRights: MXFSourceRights {
        MXFSourceRights(
            redistributable: rightsDisposition == .projectOwnedCC0,
            repositoryEligible: repositoryAllowed,
            licenseIdentifier: licenseIdentifier
        )
    }

    func sourceIdentity(size: UInt64) throws -> MXFSourceIdentity {
        try MXFSourceIdentity(
            file: MXFRelativePath("sources/\(fixtureName)"),
            sha256: sha256,
            size: size,
            profile: profile.rawValue,
            rights: sourceRights
        )
    }
}

enum SyntheticMXFSourceKit {
    static let provenance = "Generated in-repository by SyntheticMXFBuilder; no third-party media."

    static let sources: [SyntheticMXFSource] = [
        SyntheticMXFSource(
            fixtureName: "op1a-project-owned-v1.mxf.hex",
            profile: .op1a,
            sha256: "636a1205e7c2b0f4801d52c6c4e3f905693a6fba574d8506e2ec3b50d6eceaf6",
            provenance: provenance,
            repositoryAllowed: true,
            rightsDisposition: .projectOwnedCC0,
            licenseIdentifier: "CC0-1.0"
        ),
        SyntheticMXFSource(
            fixtureName: "op-atom-project-owned-v1.mxf.hex",
            profile: .opAtom,
            sha256: "3493dc1aed3097d93226b026923be3625753ca89e7b22cb810f54ecdb7a0afbc",
            provenance: provenance,
            repositoryAllowed: true,
            rightsDisposition: .projectOwnedCC0,
            licenseIdentifier: "CC0-1.0"
        )
    ]

    static func source(for profile: SyntheticMXFProfile) -> SyntheticMXFSource {
        sources.first { $0.profile == profile }!
    }
}

enum SyntheticMXFBuilder {
    private static let headerKey = partitionKey(kind: 0x02)
    private static let bodyKey = partitionKey(kind: 0x03)
    private static let footerKey = partitionKey(kind: 0x04)
    private static let essenceKey = Data([
        0x06, 0x0e, 0x2b, 0x34, 0x01, 0x02, 0x01, 0x01,
        0x0d, 0x01, 0x03, 0x01, 0x15, 0x01, 0x05, 0x01
    ])

    static func make(_ profile: SyntheticMXFProfile) -> Data {
        let essencePayloads: [Data]
        switch profile {
        case .op1a:
            essencePayloads = [Data([0x11, 0x12, 0x13, 0x14]), Data([0x21, 0x22, 0x23])]
        case .opAtom:
            essencePayloads = [Data([0xa1, 0xa2, 0xa3, 0xa4, 0xa5])]
        }

        let partitionSize: UInt64 = 16 + 1 + 88
        let headerOffset: UInt64 = 0
        let bodyOffset = partitionSize
        let essenceSize = essencePayloads.reduce(UInt64(0)) { $0 + 17 + UInt64($1.count) }
        let footerOffset = bodyOffset + partitionSize + essenceSize

        let header = klv(
            key: headerKey,
            value: partitionValue(
                this: headerOffset, previous: 0, footer: footerOffset,
                bodySID: 0, operationalPattern: operationalPattern(profile)
            )
        )
        let body = klv(
            key: bodyKey,
            value: partitionValue(
                this: bodyOffset, previous: headerOffset, footer: footerOffset,
                bodySID: 1, operationalPattern: operationalPattern(profile)
            )
        )
        let essence = essencePayloads.reduce(into: Data()) { result, payload in
            result.append(klv(key: essenceKey, value: payload))
        }
        let footer = klv(
            key: footerKey,
            value: partitionValue(
                this: footerOffset, previous: bodyOffset, footer: footerOffset,
                bodySID: 0, operationalPattern: operationalPattern(profile)
            )
        )
        return header + body + essence + footer
    }

    static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func decodeHexFixture(_ text: String) -> Data? {
        let hex = text.filter { !$0.isWhitespace }
        guard hex.count.isMultiple(of: 2), hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = Data()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        return bytes
    }

    private static func partitionKey(kind: UInt8) -> Data {
        Data([0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
              0x0d, 0x01, 0x02, 0x01, 0x01, kind, 0x04, 0x00])
    }

    private static func operationalPattern(_ profile: SyntheticMXFProfile) -> Data {
        switch profile {
        case .op1a:
            Data([0x06, 0x0e, 0x2b, 0x34, 0x04, 0x01, 0x01, 0x01,
                  0x0d, 0x01, 0x02, 0x01, 0x01, 0x01, 0x01, 0x00])
        case .opAtom:
            Data([0x06, 0x0e, 0x2b, 0x34, 0x04, 0x01, 0x01, 0x01,
                  0x0d, 0x01, 0x02, 0x01, 0x10, 0x00, 0x00, 0x00])
        }
    }

    private static func partitionValue(
        this: UInt64,
        previous: UInt64,
        footer: UInt64,
        bodySID: UInt32,
        operationalPattern: Data
    ) -> Data {
        var value = Data()
        appendUInt16(1, to: &value)
        appendUInt16(3, to: &value)
        appendUInt32(1, to: &value)
        appendUInt64(this, to: &value)
        appendUInt64(previous, to: &value)
        appendUInt64(footer, to: &value)
        appendUInt64(0, to: &value) // header byte count
        appendUInt64(0, to: &value) // index byte count
        appendUInt32(0, to: &value) // index SID
        appendUInt64(0, to: &value) // body offset
        appendUInt32(bodySID, to: &value)
        value.append(operationalPattern)
        appendUInt32(0, to: &value) // essence-container batch count
        appendUInt32(16, to: &value)
        precondition(value.count == 88)
        return value
    }

    private static func klv(key: Data, value: Data) -> Data {
        precondition(key.count == 16 && value.count < 128)
        return key + Data([UInt8(value.count)]) + value
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}
