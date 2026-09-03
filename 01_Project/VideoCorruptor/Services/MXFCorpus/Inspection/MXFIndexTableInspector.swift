import Foundation

enum MXFIndexTableField: String, CaseIterable, Equatable, Sendable {
    case indexEditRate
    case indexSID
    case bodySID
    case sliceCount
    case deltaEntryArray
    case indexEntryArray
}

/// Fixture-owned tag schema. No operational tag is inferred from a tag number or UL.
struct MXFIndexTableFieldSchema: Equatable, Sendable {
    private let fieldByTag: [UInt16: MXFIndexTableField]

    init(tags: [UInt16: MXFIndexTableField]) throws {
        var tagByField: [MXFIndexTableField: UInt16] = [:]
        for (tag, field) in tags {
            if let firstTag = tagByField[field] {
                throw MXFIndexTableSchemaError.duplicateField(
                    field: field, firstTag: firstTag, secondTag: tag
                )
            }
            tagByField[field] = tag
        }
        fieldByTag = tags
    }

    func field(for tag: UInt16) -> MXFIndexTableField? { fieldByTag[tag] }
}

enum MXFIndexTableSchemaError: Error, Equatable, Sendable {
    case duplicateField(field: MXFIndexTableField, firstTag: UInt16, secondTag: UInt16)
}

struct MXFIndexUInt32Field: Equatable, Sendable {
    let value: UInt32
    let setItem: MXFLocalSetItem
    let fieldSpan: ByteSpan
}

struct MXFIndexUInt8Field: Equatable, Sendable {
    let value: UInt8
    let setItem: MXFLocalSetItem
    let fieldSpan: ByteSpan
}

struct MXFIndexEditRate: Equatable, Sendable {
    let numerator: Int32
    let denominator: Int32
    let setItem: MXFLocalSetItem
    let numeratorSpan: ByteSpan
    let denominatorSpan: ByteSpan
}

struct MXFIndexStreamOffset: Equatable, Sendable {
    let entryIndex: UInt64
    let value: UInt64
    let entrySpan: ByteSpan
    let fieldSpan: ByteSpan
}

struct MXFIndexBatchField: Equatable, Sendable {
    let setItem: MXFLocalSetItem
    let batch: MXFBatchInspection
}

struct MXFIndexTableInspection: Equatable, Sendable {
    let setSpan: ByteSpan
    let indexEditRate: MXFIndexEditRate
    let indexSID: MXFIndexUInt32Field
    let bodySID: MXFIndexUInt32Field
    let sliceCount: MXFIndexUInt8Field
    let deltaEntryArray: MXFIndexBatchField
    let indexEntryArray: MXFIndexBatchField
    let streamOffsets: [MXFIndexStreamOffset]
}

struct MXFIndexTableRelationships: Equatable, Sendable {
    let essenceStreamSpan: ByteSpan?
    let expectedIndexSID: UInt32?
    let expectedBodySID: UInt32?

    init(
        essenceStreamSpan: ByteSpan? = nil,
        expectedIndexSID: UInt32? = nil,
        expectedBodySID: UInt32? = nil
    ) {
        self.essenceStreamSpan = essenceStreamSpan
        self.expectedIndexSID = expectedIndexSID
        self.expectedBodySID = expectedBodySID
    }
}

enum MXFIndexTableError: Error, Equatable, Sendable {
    case malformedLocalSet(MXFLocalSetError)
    case missingField(MXFIndexTableField)
    case duplicateField(field: MXFIndexTableField, firstTagSpan: ByteSpan, secondTagSpan: ByteSpan)
    case wrongWidth(field: MXFIndexTableField, expected: UInt64, actual: UInt64, valueSpan: ByteSpan?)
    case invalidBatch(field: MXFIndexTableField, error: MXFBatchInspectionError)
    case zeroEditRateDenominator(span: ByteSpan)
    case sliceCountLimitExceeded(actual: UInt64, maximum: UInt64, span: ByteSpan)
    case deltaCountLimitExceeded(actual: UInt64, maximum: UInt64, span: ByteSpan)
    case indexEntryItemTooSmall(actual: UInt64, minimum: UInt64, span: ByteSpan)
    case indexSIDMismatch(actual: UInt32, expected: UInt32, span: ByteSpan)
    case bodySIDMismatch(actual: UInt32, expected: UInt32, span: ByteSpan)
    case streamOffsetOutsideEssence(entryIndex: UInt64, value: UInt64, span: ByteSpan, essenceSpan: ByteSpan)
    case nonIncreasingStreamOffset(entryIndex: UInt64, previous: UInt64, current: UInt64, span: ByteSpan)
    case integerOverflow(field: MXFIndexTableField, offset: UInt64)
}

enum MXFIndexTableInspectionResult: Equatable, Sendable {
    case indexTable(MXFIndexTableInspection)
    case invalid(MXFIndexTableError)
}

struct MXFIndexTableInspector: Sendable {
    func inspect(
        data: Data,
        setSpan: ByteSpan,
        schema: MXFIndexTableFieldSchema,
        primerMap: MXFPrimerMap = MXFPrimerMap(),
        limits: MXFInspectionLimits = MXFInspectionLimits(),
        maximumSliceCount: UInt64 = 255,
        maximumDeltaCount: UInt64 = 1_000,
        relationships: MXFIndexTableRelationships = MXFIndexTableRelationships()
    ) -> MXFIndexTableInspectionResult {
        let local = MXFLocalSetInspector().inspect(
            data: data, enclosingSpan: setSpan, primerMap: primerMap,
            maximumItemCount: limits.maximumElementCount
        )
        if let error = local.error { return .invalid(.malformedLocalSet(error)) }

        var items: [MXFIndexTableField: MXFLocalSetItem] = [:]
        for item in local.items {
            guard let field = schema.field(for: item.tag) else { continue }
            if let first = items[field] {
                return .invalid(.duplicateField(
                    field: field, firstTagSpan: first.tagSpan, secondTagSpan: item.tagSpan
                ))
            }
            items[field] = item
        }
        for field in MXFIndexTableField.allCases where items[field] == nil {
            return .invalid(.missingField(field))
        }

        do {
            let editRate = try decodeEditRate(items[.indexEditRate]!, data: data)
            guard editRate.denominator != 0 else {
                return .invalid(.zeroEditRateDenominator(span: editRate.denominatorSpan))
            }
            let indexSID = try decodeUInt32(.indexSID, item: items[.indexSID]!, data: data)
            let bodySID = try decodeUInt32(.bodySID, item: items[.bodySID]!, data: data)
            let sliceCount = try decodeUInt8(.sliceCount, item: items[.sliceCount]!, data: data)
            guard UInt64(sliceCount.value) <= maximumSliceCount else {
                return .invalid(.sliceCountLimitExceeded(
                    actual: UInt64(sliceCount.value), maximum: maximumSliceCount,
                    span: sliceCount.fieldSpan
                ))
            }
            if let expected = relationships.expectedIndexSID, indexSID.value != expected {
                return .invalid(.indexSIDMismatch(actual: indexSID.value, expected: expected, span: indexSID.fieldSpan))
            }
            if let expected = relationships.expectedBodySID, bodySID.value != expected {
                return .invalid(.bodySIDMismatch(actual: bodySID.value, expected: expected, span: bodySID.fieldSpan))
            }

            let delta = try decodeBatch(.deltaEntryArray, item: items[.deltaEntryArray]!, data: data, limits: limits)
            guard delta.batch.header.count.value <= maximumDeltaCount else {
                return .invalid(.deltaCountLimitExceeded(
                    actual: delta.batch.header.count.value, maximum: maximumDeltaCount,
                    span: delta.batch.header.count.span
                ))
            }
            let entries = try decodeBatch(.indexEntryArray, item: items[.indexEntryArray]!, data: data, limits: limits)
            let minimumEntrySize = try CheckedBinaryArithmetic.add(
                11, CheckedBinaryArithmetic.multiply(UInt64(sliceCount.value), 4)
            )
            let actualEntrySize = entries.batch.header.itemSize.value
            guard actualEntrySize >= minimumEntrySize else {
                return .invalid(.indexEntryItemTooSmall(
                    actual: actualEntrySize, minimum: minimumEntrySize,
                    span: entries.batch.header.itemSize.span
                ))
            }
            let offsets = try decodeOffsets(entries, data: data, essenceSpan: relationships.essenceStreamSpan)
            return .indexTable(.init(
                setSpan: setSpan, indexEditRate: editRate, indexSID: indexSID,
                bodySID: bodySID, sliceCount: sliceCount, deltaEntryArray: delta,
                indexEntryArray: entries, streamOffsets: offsets
            ))
        } catch let error as MXFIndexTableError {
            return .invalid(error)
        } catch {
            return .invalid(.integerOverflow(field: .indexEntryArray, offset: setSpan.lowerBound))
        }
    }

    private func valueSpan(_ field: MXFIndexTableField, _ item: MXFLocalSetItem, width: UInt64) throws -> ByteSpan {
        guard item.ber.value == width, let span = item.valueSpan else {
            throw MXFIndexTableError.wrongWidth(
                field: field, expected: width, actual: item.ber.value, valueSpan: item.valueSpan
            )
        }
        return span
    }

    private func decodeUInt32(_ field: MXFIndexTableField, item: MXFLocalSetItem, data: Data) throws -> MXFIndexUInt32Field {
        let span = try valueSpan(field, item, width: 4)
        return .init(value: try data.checkedUInt32BE(at: span.lowerBound), setItem: item, fieldSpan: span)
    }

    private func decodeUInt8(_ field: MXFIndexTableField, item: MXFLocalSetItem, data: Data) throws -> MXFIndexUInt8Field {
        let span = try valueSpan(field, item, width: 1)
        let offset = try CheckedBinaryArithmetic.int(exactly: span.lowerBound)
        return .init(value: data[offset], setItem: item, fieldSpan: span)
    }

    private func decodeEditRate(_ item: MXFLocalSetItem, data: Data) throws -> MXFIndexEditRate {
        let span = try valueSpan(.indexEditRate, item, width: 8)
        let denominatorOffset = try CheckedBinaryArithmetic.add(span.lowerBound, 4)
        return .init(
            numerator: Int32(bitPattern: try data.checkedUInt32BE(at: span.lowerBound)),
            denominator: Int32(bitPattern: try data.checkedUInt32BE(at: denominatorOffset)),
            setItem: item,
            numeratorSpan: try ByteSpan(offset: span.lowerBound, length: 4),
            denominatorSpan: try ByteSpan(offset: denominatorOffset, length: 4)
        )
    }

    private func decodeBatch(
        _ field: MXFIndexTableField, item: MXFLocalSetItem, data: Data,
        limits: MXFInspectionLimits
    ) throws -> MXFIndexBatchField {
        guard let span = item.valueSpan else {
            throw MXFIndexTableError.wrongWidth(field: field, expected: 8, actual: 0, valueSpan: nil)
        }
        switch MXFBatchInspector().inspect(batchSpan: span, in: data, limits: limits) {
        case .batch(let batch): return .init(setItem: item, batch: batch)
        case .invalid(let error): throw MXFIndexTableError.invalidBatch(field: field, error: error)
        }
    }

    private func decodeOffsets(
        _ entries: MXFIndexBatchField, data: Data, essenceSpan: ByteSpan?
    ) throws -> [MXFIndexStreamOffset] {
        let count = entries.batch.header.count.value
        guard count > 0, let payload = entries.batch.payloadSpan else { return [] }
        let size = entries.batch.header.itemSize.value
        var result: [MXFIndexStreamOffset] = []
        var previous: UInt64?
        var index: UInt64 = 0
        while index < count {
            let entryOffset = try CheckedBinaryArithmetic.add(
                payload.lowerBound, CheckedBinaryArithmetic.multiply(index, size)
            )
            let streamOffset = try CheckedBinaryArithmetic.add(entryOffset, 3)
            let entrySpan = try ByteSpan(offset: entryOffset, length: size)
            let fieldSpan = try ByteSpan(offset: streamOffset, length: 8)
            let value = try data.checkedUInt64BE(at: streamOffset)
            if let essenceSpan, value >= essenceSpan.length {
                throw MXFIndexTableError.streamOffsetOutsideEssence(
                    entryIndex: index, value: value, span: fieldSpan, essenceSpan: essenceSpan
                )
            }
            if let previous, value <= previous {
                throw MXFIndexTableError.nonIncreasingStreamOffset(
                    entryIndex: index, previous: previous, current: value, span: fieldSpan
                )
            }
            result.append(.init(entryIndex: index, value: value, entrySpan: entrySpan, fieldSpan: fieldSpan))
            previous = value
            index = try CheckedBinaryArithmetic.add(index, 1)
        }
        return result
    }
}
