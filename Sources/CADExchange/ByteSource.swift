import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

public protocol ByteSource {
    var count: Int { get }

    func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) throws -> Result
}

public extension ByteSource {
    func withNoCopyData<Result>(_ body: (Data) throws -> Result) throws -> Result {
        try withUnsafeBytes { bytes in
            let data = try bytes.noCopyData(in: 0..<bytes.count)
            return try body(data)
        }
    }
}

public struct BorrowedBytes: ByteSource, Sendable {
    private let storage: Data

    public init(_ data: Data) {
        storage = data
    }

    public var count: Int {
        storage.count
    }

    public func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) throws -> Result {
        try storage.withUnsafeBytes(body)
    }
}

extension Data: ByteSource {}

public enum ByteSourceError: Error, Equatable, Sendable {
    case fileOpenFailure(String)
    case fileReadFailure(String)
    case fileMapFailure(String)
    case fileCloseFailure(String)
    case fileTooLarge(String)
}

public final class MappedFileByteSource: ByteSource {
    #if os(WASI)
    public init(url: URL) throws {
        throw ByteSourceError.fileMapFailure("Memory-mapped byte sources are unavailable on WASI for \(url.path).")
    }
    #else
    private let pointer: UnsafeMutableRawPointer?
    private let byteCount: Int

    public init(url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw ByteSourceError.fileOpenFailure(String(cString: strerror(errno)))
        }
        var status = stat()
        guard DarwinByteSourceBridge.fstat(descriptor, &status) == 0 else {
            let message = String(cString: strerror(errno))
            _ = DarwinByteSourceBridge.close(descriptor)
            throw ByteSourceError.fileReadFailure(message)
        }
        guard status.st_size >= 0,
              UInt64(status.st_size) <= UInt64(Int.max) else {
            _ = DarwinByteSourceBridge.close(descriptor)
            throw ByteSourceError.fileTooLarge(url.path)
        }
        byteCount = Int(status.st_size)
        if byteCount == 0 {
            pointer = nil
            _ = DarwinByteSourceBridge.close(descriptor)
            return
        }
        let mappedPointer = DarwinByteSourceBridge.mmap(
            nil,
            byteCount,
            PROT_READ,
            MAP_PRIVATE,
            descriptor,
            0
        )
        let closeResult = DarwinByteSourceBridge.close(descriptor)
        guard mappedPointer != MAP_FAILED else {
            throw ByteSourceError.fileMapFailure(String(cString: strerror(errno)))
        }
        guard closeResult == 0 else {
            _ = DarwinByteSourceBridge.munmap(mappedPointer, byteCount)
            throw ByteSourceError.fileCloseFailure(String(cString: strerror(errno)))
        }
        pointer = mappedPointer
    }
    #endif

    deinit {
        #if !os(WASI)
        if let pointer {
            _ = DarwinByteSourceBridge.munmap(pointer, byteCount)
        }
        #endif
    }

    public var count: Int {
        #if os(WASI)
        0
        #else
        byteCount
        #endif
    }

    public func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) throws -> Result {
        #if os(WASI)
        throw ByteSourceError.fileMapFailure("Memory-mapped byte sources are unavailable on WASI.")
        #else
        try body(UnsafeRawBufferPointer(start: pointer, count: byteCount))
        #endif
    }
}

private enum DarwinByteSourceBridge {
    static func close(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.close(descriptor)
        #elseif canImport(Glibc)
        Glibc.close(descriptor)
        #elseif canImport(WASILibc)
        WASILibc.close(descriptor)
        #else
        -1
        #endif
    }

    static func fstat(_ descriptor: Int32, _ status: UnsafeMutablePointer<stat>) -> Int32 {
        #if canImport(Darwin)
        Darwin.fstat(descriptor, status)
        #elseif canImport(Glibc)
        Glibc.fstat(descriptor, status)
        #elseif canImport(WASILibc)
        WASILibc.fstat(descriptor, status)
        #else
        -1
        #endif
    }

    static func mmap(
        _ address: UnsafeMutableRawPointer?,
        _ length: Int,
        _ protection: Int32,
        _ flags: Int32,
        _ descriptor: Int32,
        _ offset: off_t
    ) -> UnsafeMutableRawPointer {
        #if canImport(Darwin)
        Darwin.mmap(address, length, protection, flags, descriptor, offset)
        #elseif canImport(Glibc)
        Glibc.mmap(address, length, protection, flags, descriptor, offset)
        #else
        UnsafeMutableRawPointer(bitPattern: -1)!
        #endif
    }

    static func munmap(_ address: UnsafeMutableRawPointer, _ length: Int) -> Int32 {
        #if canImport(Darwin)
        Darwin.munmap(address, length)
        #elseif canImport(Glibc)
        Glibc.munmap(address, length)
        #else
        -1
        #endif
    }
}
