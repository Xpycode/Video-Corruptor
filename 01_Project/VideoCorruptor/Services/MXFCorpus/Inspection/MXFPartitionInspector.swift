import Foundation

enum MXFPartitionKind: Equatable, Sendable {
    case header
    case body
    case footer
}

enum MXFPartitionClosure: Equatable, Sendable {
    case open
    case closed
}

enum MXFPartitionCompleteness: Equatable, Sendable {
    case incomplete
    case complete
}

struct MXFPartitionKeyClassification: Equatable, Sendable {
    let kind: MXFPartitionKind
    let closure: MXFPartitionClosure
    let completeness: MXFPartitionCompleteness
}

enum MXFPartitionFixedField: String, Equatable, Sendable {
    case majorVersion
    case minorVersion
    case kagSize
    case thisPartition
    case previousPartition
    case footerPartition
    case headerByteCount
    case indexByteCount
    case indexSID
    case bodyOffset
    case bodySID
    case operationalPattern
    case essenceContainerCount
    case essenceContainerElementSize
}

struct MXFUInt16PartitionField: Equatable, Sendable {
    let value: UInt16
    let span: ByteSpan
}

struct MXFUInt32PartitionField: Equatable, Sendable {
    let value: UInt32
    let span: ByteSpan
}

struct MXFUInt64PartitionField: Equatable, Sendable {
    let value: UInt64
    let span: ByteSpan
}

struct MXFDataPartitionField: Equatable, Sendable {
    let value: Data
    let span: ByteSpan
}

struct MXFPartitionPackInspection: Equatable, Sendable {
    /// Classification derived solely from the physical UL key.
    let keyClassification: MXFPartitionKeyClassification
    let keySpan: ByteSpan
    let valueSpan: ByteSpan
    let majorVersion: MXFUInt16PartitionField
    let minorVersion: MXFUInt16PartitionField
    let kagSize: MXFUInt32PartitionField
    let thisPartition: MXFUInt64PartitionField
    let previousPartition: MXFUInt64PartitionField
    let footerPartition: MXFUInt64PartitionField
    let headerByteCount: MXFUInt64PartitionField
    let indexByteCount: MXFUInt64PartitionField
    let indexSID: MXFUInt32PartitionField
    let bodyOffset: MXFUInt64PartitionField
    let bodySID: MXFUInt32PartitionField
    let operationalPattern: MXFDataPartitionField
    let essenceContainerCount: MXFUInt32PartitionField
    let essenceContainerElementSize: MXFUInt32PartitionField
}

enum MXFPartitionInspectionError: Error, Equatable, Sendable {
    case invalidKeySpan(ByteSpan)
    case declaredValueExceedsAvailable(declared: ByteSpan, availableByteCount: UInt64)
    case truncatedFixedField(
        field: MXFPartitionFixedField,
        requiredSpan: ByteSpan,
        availableValueSpan: ByteSpan?
    )
    case integerOverflow
}

enum MXFPartitionInspectionResult: Equatable, Sendable {
    case notPartitionPack
    case partitionPack(MXFPartitionPackInspection)
    case invalid(MXFPartitionInspectionError)
}

struct MXFPartitionInspector: Sendable {
    static let fixedValueByteCount: UInt64 = 88

    private static let keyPrefix: [UInt8] = [
        0x06, 0x0e, 0x2b, 0x34, 0x02, 0x05, 0x01, 0x01,
        0x0d, 0x01, 0x02, 0x01
    ]

    func classify(key: Data) -> MXFPartitionKeyClassification? {
        guard key.count == 16 else { return nil }
        let bytes = [UInt8](key)
        guard Array(bytes[0..<12]) == Self.keyPrefix,
              bytes[12] == 0x01,
              bytes[15] == 0x00 else {
            return nil
        }

        let kind: MXFPartitionKind
        switch bytes[13] {
        case 0x02: kind = .header
        case 0x03: kind = .body
        case 0x04: kind = .footer
        default: return nil
        }

        let closure: MXFPartitionClosure
        let completeness: MXFPartitionCompleteness
        switch bytes[14] {
        case 0x01: (closure, completeness) = (.open, .incomplete)
        case 0x02: (closure, completeness) = (.closed, .incomplete)
        case 0x03: (closure, completeness) = (.open, .complete)
        case 0x04: (closure, completeness) = (.closed, .complete)
        default: return nil
        }
        return MXFPartitionKeyClassification(
            kind: kind,
            closure: closure,
            completeness: completeness
        )
    }

    func inspect(element: MXFInspectedElement, in data: Data) -> MXFPartitionInspectionResult {
        guard let valueSpan = element.valueSpan else {
            guard classify(key: element.key) != nil else { return .notPartitionPack }
            return truncatedResult(keySpan: element.keySpan, valueOffset: element.ber.physicalSpan.upperBound,
                                   declaredValueLength: 0, availableValueLength: 0)
        }
        return inspect(key: element.key, keySpan: element.keySpan, valueSpan: valueSpan, in: data)
    }

    func inspect(
        key: Data,
        keySpan: ByteSpan,
        valueSpan: ByteSpan,
        in data: Data
    ) -> MXFPartitionInspectionResult {
        guard let classification = classify(key: key) else { return .notPartitionPack }
        guard keySpan.length == 16 else { return .invalid(.invalidKeySpan(keySpan)) }

        let availableByteCount: UInt64
        do {
            availableByteCount = try CheckedBinaryArithmetic.uint64(exactly: data.count)
        } catch {
            return .invalid(.integerOverflow)
        }
        guard valueSpan.lowerBound <= availableByteCount else {
            return truncatedResult(keySpan: keySpan, valueOffset: valueSpan.lowerBound,
                                   declaredValueLength: valueSpan.length, availableValueLength: 0)
        }
        let physicallyAvailable = availableByteCount - valueSpan.lowerBound
        let availableWithinDeclaredValue = min(valueSpan.length, physicallyAvailable)
        guard availableWithinDeclaredValue >= Self.fixedValueByteCount else {
            return truncatedResult(keySpan: keySpan, valueOffset: valueSpan.lowerBound,
                                   declaredValueLength: valueSpan.length,
                                   availableValueLength: availableWithinDeclaredValue)
        }

        do {
            let base = valueSpan.lowerBound
            func span(_ relativeOffset: UInt64, _ length: UInt64) throws -> ByteSpan {
                try ByteSpan(offset: CheckedBinaryArithmetic.add(base, relativeOffset), length: length)
            }
            func u16(_ relativeOffset: UInt64) throws -> MXFUInt16PartitionField {
                let fieldSpan = try span(relativeOffset, 2)
                return MXFUInt16PartitionField(value: try data.checkedUInt16BE(at: fieldSpan.lowerBound), span: fieldSpan)
            }
            func u32(_ relativeOffset: UInt64) throws -> MXFUInt32PartitionField {
                let fieldSpan = try span(relativeOffset, 4)
                return MXFUInt32PartitionField(value: try data.checkedUInt32BE(at: fieldSpan.lowerBound), span: fieldSpan)
            }
            func u64(_ relativeOffset: UInt64) throws -> MXFUInt64PartitionField {
                let fieldSpan = try span(relativeOffset, 8)
                return MXFUInt64PartitionField(value: try data.checkedUInt64BE(at: fieldSpan.lowerBound), span: fieldSpan)
            }
            let operationalPatternSpan = try span(64, 16)
            return .partitionPack(MXFPartitionPackInspection(
                keyClassification: classification,
                keySpan: keySpan,
                valueSpan: valueSpan,
                majorVersion: try u16(0),
                minorVersion: try u16(2),
                kagSize: try u32(4),
                thisPartition: try u64(8),
                previousPartition: try u64(16),
                footerPartition: try u64(24),
                headerByteCount: try u64(32),
                indexByteCount: try u64(40),
                indexSID: try u32(48),
                bodyOffset: try u64(52),
                bodySID: try u32(60),
                operationalPattern: MXFDataPartitionField(
                    value: try data.checkedBytes(in: operationalPatternSpan),
                    span: operationalPatternSpan
                ),
                essenceContainerCount: try u32(80),
                essenceContainerElementSize: try u32(84)
            ))
        } catch {
            return .invalid(.integerOverflow)
        }
    }

    func inspect(
        fileAt url: URL,
        key: Data,
        keySpan: ByteSpan,
        valueOffset: UInt64,
        declaredValueLength: UInt64
    ) throws -> MXFPartitionInspectionResult {
        guard classify(key: key) != nil else { return .notPartitionPack }
        guard keySpan.length == 16 else { return .invalid(.invalidKeySpan(keySpan)) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard valueOffset <= fileSize else {
            return truncatedResult(keySpan: keySpan, valueOffset: valueOffset,
                                   declaredValueLength: declaredValueLength, availableValueLength: 0)
        }
        let available = min(declaredValueLength, fileSize - valueOffset)
        guard available >= Self.fixedValueByteCount else {
            return truncatedResult(keySpan: keySpan, valueOffset: valueOffset,
                                   declaredValueLength: declaredValueLength, availableValueLength: available)
        }
        try handle.seek(toOffset: valueOffset)
        let bytes = try handle.read(upToCount: Int(Self.fixedValueByteCount)) ?? Data()
        guard bytes.count == Int(Self.fixedValueByteCount) else {
            return truncatedResult(keySpan: keySpan, valueOffset: valueOffset,
                                   declaredValueLength: declaredValueLength,
                                   availableValueLength: UInt64(bytes.count))
        }
        let localSpan = try ByteSpan(offset: 0, length: Self.fixedValueByteCount)
        let local = inspect(key: key, keySpan: try ByteSpan(offset: 0, length: 16),
                            valueSpan: localSpan, in: bytes)
        guard case .partitionPack(let parsed) = local else { return local }
        return offset(parsed, keySpan: keySpan, valueOffset: valueOffset,
                      declaredValueLength: declaredValueLength)
    }

    private func truncatedResult(
        keySpan: ByteSpan,
        valueOffset: UInt64,
        declaredValueLength: UInt64,
        availableValueLength: UInt64
    ) -> MXFPartitionInspectionResult {
        let fields: [(MXFPartitionFixedField, UInt64, UInt64)] = [
            (.majorVersion, 0, 2), (.minorVersion, 2, 2), (.kagSize, 4, 4),
            (.thisPartition, 8, 8), (.previousPartition, 16, 8), (.footerPartition, 24, 8),
            (.headerByteCount, 32, 8), (.indexByteCount, 40, 8), (.indexSID, 48, 4),
            (.bodyOffset, 52, 8), (.bodySID, 60, 4), (.operationalPattern, 64, 16),
            (.essenceContainerCount, 80, 4), (.essenceContainerElementSize, 84, 4)
        ]
        for (field, relativeOffset, length) in fields where availableValueLength < relativeOffset + length {
            do {
                let required = try ByteSpan(offset: CheckedBinaryArithmetic.add(valueOffset, relativeOffset), length: length)
                let availableSpan = availableValueLength == 0 ? nil : try ByteSpan(offset: valueOffset, length: availableValueLength)
                return .invalid(.truncatedFixedField(field: field, requiredSpan: required,
                                                     availableValueSpan: availableSpan))
            } catch {
                return .invalid(.integerOverflow)
            }
        }
        _ = keySpan
        _ = declaredValueLength
        return .invalid(.integerOverflow)
    }

    private func offset(
        _ parsed: MXFPartitionPackInspection,
        keySpan: ByteSpan,
        valueOffset: UInt64,
        declaredValueLength: UInt64
    ) -> MXFPartitionInspectionResult {
        do {
            func shifted(_ span: ByteSpan) throws -> ByteSpan {
                try ByteSpan(offset: CheckedBinaryArithmetic.add(valueOffset, span.lowerBound), length: span.length)
            }
            func f16(_ field: MXFUInt16PartitionField) throws -> MXFUInt16PartitionField { .init(value: field.value, span: try shifted(field.span)) }
            func f32(_ field: MXFUInt32PartitionField) throws -> MXFUInt32PartitionField { .init(value: field.value, span: try shifted(field.span)) }
            func f64(_ field: MXFUInt64PartitionField) throws -> MXFUInt64PartitionField { .init(value: field.value, span: try shifted(field.span)) }
            return .partitionPack(.init(
                keyClassification: parsed.keyClassification, keySpan: keySpan,
                valueSpan: try ByteSpan(offset: valueOffset, length: declaredValueLength),
                majorVersion: try f16(parsed.majorVersion), minorVersion: try f16(parsed.minorVersion),
                kagSize: try f32(parsed.kagSize), thisPartition: try f64(parsed.thisPartition),
                previousPartition: try f64(parsed.previousPartition), footerPartition: try f64(parsed.footerPartition),
                headerByteCount: try f64(parsed.headerByteCount), indexByteCount: try f64(parsed.indexByteCount),
                indexSID: try f32(parsed.indexSID), bodyOffset: try f64(parsed.bodyOffset),
                bodySID: try f32(parsed.bodySID),
                operationalPattern: .init(value: parsed.operationalPattern.value, span: try shifted(parsed.operationalPattern.span)),
                essenceContainerCount: try f32(parsed.essenceContainerCount),
                essenceContainerElementSize: try f32(parsed.essenceContainerElementSize)
            ))
        } catch {
            return .invalid(.integerOverflow)
        }
    }
}
