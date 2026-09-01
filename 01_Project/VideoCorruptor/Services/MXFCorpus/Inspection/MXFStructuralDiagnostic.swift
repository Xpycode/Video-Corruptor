enum MXFStructuralDiagnostic: Equatable, Sendable {
    case invalidTrustedStart(offset: UInt64, inputByteCount: UInt64)
    case truncatedKey(offset: UInt64, availableByteCount: UInt64)
    case malformedBER(offset: UInt64, error: MXFBERError)
    case truncatedValue(offset: UInt64, declaredByteCount: UInt64, availableByteCount: UInt64)
    case nonCanonicalBER(offset: UInt64, diagnostic: MXFBERDiagnostic)
    case integerOverflow(offset: UInt64, operation: MXFStructuralArithmeticOperation)
    case limitExceeded(limit: MXFInspectionLimit, actual: UInt64, maximum: UInt64)
    case cancelled(checkpoint: MXFInspectionCheckpoint)
}

enum MXFStructuralArithmeticOperation: Equatable, Sendable {
    case keyEnd
    case berOffset
    case valueOffset
    case valueEnd
}
