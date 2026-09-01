import Foundation

struct MXFStructuralInspector: Sendable {
    private static let keyByteCount: UInt64 = 16

    func inspect(
        data: Data,
        trustedStartOffset: UInt64 = 0,
        limits: MXFInspectionLimits = MXFInspectionLimits(),
        shouldCancel: MXFInspectionCancellationCheck = { _ in false }
    ) -> MXFInspectedFile {
        let inputByteCount: UInt64
        do {
            inputByteCount = try CheckedBinaryArithmetic.uint64(exactly: data.count)
        } catch {
            return result(
                inputByteCount: .max,
                trustedStartOffset: trustedStartOffset,
                diagnostics: [.integerOverflow(offset: trustedStartOffset, operation: .keyEnd)]
            )
        }

        if shouldCancel(.beforeInspection) {
            return result(
                inputByteCount: inputByteCount,
                trustedStartOffset: trustedStartOffset,
                diagnostics: [.cancelled(checkpoint: .beforeInspection)]
            )
        }
        guard inputByteCount <= limits.maximumInputBytes else {
            return result(
                inputByteCount: inputByteCount,
                trustedStartOffset: trustedStartOffset,
                diagnostics: [.limitExceeded(
                    limit: .inputBytes,
                    actual: inputByteCount,
                    maximum: limits.maximumInputBytes
                )]
            )
        }
        guard trustedStartOffset <= inputByteCount else {
            return result(
                inputByteCount: inputByteCount,
                trustedStartOffset: trustedStartOffset,
                diagnostics: [.invalidTrustedStart(
                    offset: trustedStartOffset,
                    inputByteCount: inputByteCount
                )]
            )
        }

        var offset = trustedStartOffset
        var elements: [MXFInspectedElement] = []
        var diagnostics: [MXFStructuralDiagnostic] = []
        var partialElement: MXFPartialElement?
        var candidateCount: UInt64 = 0

        while offset < inputByteCount {
            let beforeElement = MXFInspectionCheckpoint.beforeElement(offset: offset)
            if shouldCancel(beforeElement) {
                diagnostics.append(.cancelled(checkpoint: beforeElement))
                break
            }
            guard candidateCount < limits.maximumElementCount else {
                diagnostics.append(.limitExceeded(
                    limit: .elementCount,
                    actual: incremented(candidateCount),
                    maximum: limits.maximumElementCount
                ))
                break
            }
            candidateCount = incremented(candidateCount)

            let remaining = inputByteCount - offset
            guard remaining >= Self.keyByteCount else {
                let availableSpan = optionalSpan(offset: offset, length: remaining)
                partialElement = .truncatedKey(offset: offset, availableSpan: availableSpan)
                diagnostics.append(.truncatedKey(offset: offset, availableByteCount: remaining))
                break
            }
            guard Self.keyByteCount <= limits.maximumAllocationBytes else {
                diagnostics.append(.limitExceeded(
                    limit: .allocationBytes,
                    actual: Self.keyByteCount,
                    maximum: limits.maximumAllocationBytes
                ))
                break
            }

            let keySpan: ByteSpan
            let berOffset: UInt64
            do {
                keySpan = try ByteSpan(offset: offset, length: Self.keyByteCount)
                berOffset = try CheckedBinaryArithmetic.add(offset, Self.keyByteCount)
            } catch {
                diagnostics.append(.integerOverflow(offset: offset, operation: .keyEnd))
                break
            }

            let key: Data
            do {
                key = try data.checkedBytes(in: keySpan)
            } catch {
                diagnostics.append(.truncatedKey(offset: offset, availableByteCount: remaining))
                partialElement = .truncatedKey(offset: offset, availableSpan: nil)
                break
            }

            let ber: MXFBERDecodedLength
            do {
                ber = try MXFBER.decodeLength(
                    from: data,
                    at: berOffset,
                    maximumValue: limits.maximumBERValueLength
                )
            } catch let error as MXFBERError {
                if case .lengthLimitExceeded(let value, let limit) = error {
                    diagnostics.append(.limitExceeded(
                        limit: .berValueLength,
                        actual: value,
                        maximum: limit
                    ))
                } else {
                    diagnostics.append(.malformedBER(offset: berOffset, error: error))
                }
                partialElement = .malformedBER(keySpan: keySpan, berOffset: berOffset)
                break
            } catch {
                diagnostics.append(.integerOverflow(offset: berOffset, operation: .berOffset))
                partialElement = .malformedBER(keySpan: keySpan, berOffset: berOffset)
                break
            }

            for warning in ber.diagnostics {
                diagnostics.append(.nonCanonicalBER(offset: berOffset, diagnostic: warning))
            }
            let afterBER = MXFInspectionCheckpoint.afterBER(offset: berOffset)
            if shouldCancel(afterBER) {
                diagnostics.append(.cancelled(checkpoint: afterBER))
                break
            }
            guard ber.value <= limits.maximumAllocationBytes else {
                diagnostics.append(.limitExceeded(
                    limit: .allocationBytes,
                    actual: ber.value,
                    maximum: limits.maximumAllocationBytes
                ))
                break
            }

            let valueOffset: UInt64
            let valueEnd: UInt64
            do {
                valueOffset = try CheckedBinaryArithmetic.add(berOffset, ber.encodedWidth)
            } catch {
                diagnostics.append(.integerOverflow(offset: berOffset, operation: .valueOffset))
                break
            }
            do {
                valueEnd = try CheckedBinaryArithmetic.add(valueOffset, ber.value)
            } catch {
                diagnostics.append(.integerOverflow(offset: valueOffset, operation: .valueEnd))
                break
            }

            guard valueEnd <= inputByteCount else {
                let availableValueByteCount = inputByteCount - valueOffset
                let availableSpan = optionalSpan(
                    offset: valueOffset,
                    length: availableValueByteCount
                )
                partialElement = .truncatedValue(
                    keySpan: keySpan,
                    ber: ber,
                    valueOffset: valueOffset,
                    availableValueSpan: availableSpan
                )
                diagnostics.append(.truncatedValue(
                    offset: valueOffset,
                    declaredByteCount: ber.value,
                    availableByteCount: availableValueByteCount
                ))
                break
            }

            do {
                let physicalSpan = try ByteSpan(lowerBound: offset, upperBound: valueEnd)
                let valueSpan = ber.value == 0
                    ? nil
                    : try ByteSpan(offset: valueOffset, length: ber.value)
                elements.append(MXFInspectedElement(
                    key: key,
                    keySpan: keySpan,
                    ber: ber,
                    valueSpan: valueSpan,
                    physicalSpan: physicalSpan
                ))
            } catch {
                diagnostics.append(.integerOverflow(offset: offset, operation: .valueEnd))
                break
            }

            offset = valueEnd
            let afterElement = MXFInspectionCheckpoint.afterElement(offset: offset)
            if shouldCancel(afterElement) {
                diagnostics.append(.cancelled(checkpoint: afterElement))
                break
            }
        }

        return MXFInspectedFile(
            inputByteCount: inputByteCount,
            trustedStartOffset: trustedStartOffset,
            elements: elements,
            partialElement: partialElement,
            counters: MXFInspectionCounters(
                candidateCount: candidateCount,
                completeElementCount: UInt64(elements.count),
                inspectedByteCount: offset - trustedStartOffset
            ),
            diagnostics: diagnostics,
            completedWalk: offset == inputByteCount && containsOnlyWarnings(diagnostics)
        )
    }

    private func result(
        inputByteCount: UInt64,
        trustedStartOffset: UInt64,
        diagnostics: [MXFStructuralDiagnostic]
    ) -> MXFInspectedFile {
        MXFInspectedFile(
            inputByteCount: inputByteCount,
            trustedStartOffset: trustedStartOffset,
            elements: [],
            partialElement: nil,
            counters: MXFInspectionCounters(
                candidateCount: 0,
                completeElementCount: 0,
                inspectedByteCount: 0
            ),
            diagnostics: diagnostics,
            completedWalk: diagnostics.isEmpty
        )
    }

    private func incremented(_ value: UInt64) -> UInt64 {
        let (result, overflow) = value.addingReportingOverflow(1)
        return overflow ? .max : result
    }

    private func optionalSpan(offset: UInt64, length: UInt64) -> ByteSpan? {
        guard length > 0 else { return nil }
        do {
            return try ByteSpan(offset: offset, length: length)
        } catch {
            return nil
        }
    }

    private func containsOnlyWarnings(_ diagnostics: [MXFStructuralDiagnostic]) -> Bool {
        diagnostics.allSatisfy { diagnostic in
            if case .nonCanonicalBER = diagnostic {
                return true
            }
            return false
        }
    }
}
