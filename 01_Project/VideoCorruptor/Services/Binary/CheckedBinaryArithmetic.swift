enum CheckedBinaryError: Error, Equatable, Sendable {
    case additionOverflow(lhs: UInt64, rhs: UInt64)
    case multiplicationOverflow(lhs: UInt64, rhs: UInt64)
    case uint64DoesNotFitInt(UInt64)
    case negativeIntDoesNotFitUInt64(Int)
    case emptySpan(offset: UInt64)
    case invalidSpanBounds(lowerBound: UInt64, upperBound: UInt64)
}

enum CheckedBinaryArithmetic {
    static func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw CheckedBinaryError.additionOverflow(lhs: lhs, rhs: rhs)
        }
        return result
    }

    static func multiply(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw CheckedBinaryError.multiplicationOverflow(lhs: lhs, rhs: rhs)
        }
        return result
    }

    static func int(exactly value: UInt64) throws -> Int {
        guard let result = Int(exactly: value) else {
            throw CheckedBinaryError.uint64DoesNotFitInt(value)
        }
        return result
    }

    static func uint64(exactly value: Int) throws -> UInt64 {
        guard let result = UInt64(exactly: value) else {
            throw CheckedBinaryError.negativeIntDoesNotFitUInt64(value)
        }
        return result
    }
}
