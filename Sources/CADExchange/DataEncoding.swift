import Foundation

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendLittleEndianFloat32(_ value: Float32) {
        appendLittleEndian(value.bitPattern)
    }
}

extension UnsafeRawBufferPointer {
    func littleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count - 2 else {
            throw ZipArchiveError.truncatedArchive
        }
        return UInt16(relativeByte(at: offset))
            | (UInt16(relativeByte(at: offset + 1)) << 8)
    }

    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= count - 4 else {
            throw ZipArchiveError.truncatedArchive
        }
        return UInt32(relativeByte(at: offset))
            | (UInt32(relativeByte(at: offset + 1)) << 8)
            | (UInt32(relativeByte(at: offset + 2)) << 16)
            | (UInt32(relativeByte(at: offset + 3)) << 24)
    }

    func littleEndianFloat32(at offset: Int) throws -> Float32 {
        Float32(bitPattern: try littleEndianUInt32(at: offset))
    }

    func noCopyData(in range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0,
              range.upperBound <= count,
              range.lowerBound <= range.upperBound else {
            throw ZipArchiveError.truncatedArchive
        }
        guard range.count > 0 else {
            return Data()
        }
        guard let baseAddress else {
            throw ZipArchiveError.truncatedArchive
        }
        return Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: baseAddress.advanced(by: range.lowerBound)),
            count: range.count,
            deallocator: .none
        )
    }

    private func relativeByte(at offset: Int) -> UInt8 {
        self[offset]
    }
}

extension Data {
    func littleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= count - 2 else {
            throw ZipArchiveError.truncatedArchive
        }
        return UInt16(relativeByte(at: offset))
            | (UInt16(relativeByte(at: offset + 1)) << 8)
    }

    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= count - 4 else {
            throw ZipArchiveError.truncatedArchive
        }
        return UInt32(relativeByte(at: offset))
            | (UInt32(relativeByte(at: offset + 1)) << 8)
            | (UInt32(relativeByte(at: offset + 2)) << 16)
            | (UInt32(relativeByte(at: offset + 3)) << 24)
    }

    func littleEndianFloat32(at offset: Int) throws -> Float32 {
        Float32(bitPattern: try littleEndianUInt32(at: offset))
    }

    private func relativeByte(at offset: Int) -> UInt8 {
        self[index(startIndex, offsetBy: offset)]
    }
}
