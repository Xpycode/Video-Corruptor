struct ByteSpan: Equatable, Hashable, Sendable {
    let lowerBound: UInt64
    let upperBound: UInt64

    init(lowerBound: UInt64, upperBound: UInt64) throws {
        guard lowerBound < upperBound else {
            if lowerBound == upperBound {
                throw CheckedBinaryError.emptySpan(offset: lowerBound)
            }
            throw CheckedBinaryError.invalidSpanBounds(
                lowerBound: lowerBound,
                upperBound: upperBound
            )
        }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    init(offset: UInt64, length: UInt64) throws {
        guard length > 0 else {
            throw CheckedBinaryError.emptySpan(offset: offset)
        }
        try self.init(
            lowerBound: offset,
            upperBound: CheckedBinaryArithmetic.add(offset, length)
        )
    }

    var length: UInt64 {
        upperBound - lowerBound
    }

    var range: Range<UInt64> {
        lowerBound..<upperBound
    }

    func contains(_ offset: UInt64) -> Bool {
        lowerBound <= offset && offset < upperBound
    }

    func contains(_ other: ByteSpan) -> Bool {
        lowerBound <= other.lowerBound && other.upperBound <= upperBound
    }

    func overlaps(_ other: ByteSpan) -> Bool {
        lowerBound < other.upperBound && other.lowerBound < upperBound
    }
}
