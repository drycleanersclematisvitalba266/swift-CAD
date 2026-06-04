import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

public protocol ByteSink {
    func write(_ bytes: UnsafeRawBufferPointer) throws
}

public enum ByteSinkError: Error, Equatable, Sendable {
    case fileOpenFailure(String)
    case fileWriteFailure(String)
    case fileCloseFailure(String)
    case fileReplaceFailure(String)
}

public final class DataByteSink: ByteSink {
    private var storage = Data()

    public init() {}

    public var bytes: Data {
        storage
    }

    public func write(_ bytes: UnsafeRawBufferPointer) throws {
        storage.append(contentsOf: bytes)
    }
}

public final class FileByteSink: ByteSink {
    #if os(WASI)
    private let handle: FileHandle
    #else
    private let descriptor: Int32
    #endif
    private var isClosed = false

    public init(url: URL) throws {
        #if os(WASI)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ByteSinkError.fileOpenFailure("Failed to create file at \(url.path).")
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw ByteSinkError.fileOpenFailure(error.localizedDescription)
        }
        #else
        descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            throw ByteSinkError.fileOpenFailure(String(cString: strerror(errno)))
        }
        #endif
    }

    deinit {
        if !isClosed {
            #if os(WASI)
            handle.closeFile()
            #else
            _ = DarwinBridge.close(descriptor)
            #endif
        }
    }

    public func write(_ bytes: UnsafeRawBufferPointer) throws {
        #if os(WASI)
        let data = Data(bytes)
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw ByteSinkError.fileWriteFailure(error.localizedDescription)
        }
        #else
        guard var baseAddress = bytes.baseAddress else {
            return
        }
        var remaining = bytes.count
        while remaining > 0 {
            let written = DarwinBridge.write(descriptor, baseAddress, remaining)
            if written < 0, errno == EINTR {
                continue
            }
            if written == 0 {
                throw ByteSinkError.fileWriteFailure("File write returned zero bytes.")
            }
            guard written > 0 else {
                throw ByteSinkError.fileWriteFailure(String(cString: strerror(errno)))
            }
            remaining -= written
            baseAddress = baseAddress.advanced(by: written)
        }
        #endif
    }

    public func close() throws {
        guard !isClosed else {
            return
        }
        #if os(WASI)
        do {
            try handle.close()
        } catch {
            throw ByteSinkError.fileCloseFailure(error.localizedDescription)
        }
        #else
        guard DarwinBridge.close(descriptor) == 0 else {
            throw ByteSinkError.fileCloseFailure(String(cString: strerror(errno)))
        }
        #endif
        isClosed = true
    }
}

func writeFileAtomically(to url: URL, operation: (any ByteSink) throws -> Void) throws {
    let fileManager = FileManager.default
    let directoryURL = url.deletingLastPathComponent()
    let temporaryURL = directoryURL.appendingPathComponent(
        ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
    )
    let sink = try FileByteSink(url: temporaryURL)
    do {
        try operation(sink)
        try sink.close()
        try replaceFile(at: temporaryURL, with: url)
    } catch {
        let primaryError = error
        do {
            try sink.close()
        } catch {
        }
        do {
            try fileManager.removeItem(at: temporaryURL)
        } catch {
        }
        throw primaryError
    }
}

public extension ByteSink {
    func write(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            try write(bytes)
        }
    }

    func writeByte(_ byte: UInt8) throws {
        var value = byte
        try Swift.withUnsafeBytes(of: &value) { bytes in
            try write(bytes)
        }
    }

    func writeLittleEndian<T: FixedWidthInteger>(_ value: T) throws {
        var littleEndian = value.littleEndian
        try Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            try write(bytes)
        }
    }

    func writeLittleEndianFloat32(_ value: Float32) throws {
        try writeLittleEndian(value.bitPattern)
    }

    func writeUTF8(_ string: String) throws {
        var wroteContiguousStorage = false
        try string.utf8.withContiguousStorageIfAvailable { buffer in
            wroteContiguousStorage = true
            try write(UnsafeRawBufferPointer(buffer))
        }
        if !wroteContiguousStorage {
            for byte in string.utf8 {
                try writeByte(byte)
            }
        }
    }
}

private enum DarwinBridge {
    static func write(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(descriptor, buffer, count)
        #elseif canImport(Glibc)
        Glibc.write(descriptor, buffer, count)
        #elseif canImport(WASILibc)
        WASILibc.write(descriptor, buffer, count)
        #else
        -1
        #endif
    }

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

    static func rename(_ oldPath: String, _ newPath: String) -> Int32 {
        #if canImport(Darwin)
        Darwin.rename(oldPath, newPath)
        #elseif canImport(Glibc)
        Glibc.rename(oldPath, newPath)
        #elseif canImport(WASILibc)
        WASILibc.rename(oldPath, newPath)
        #else
        -1
        #endif
    }
}

private func replaceFile(at temporaryURL: URL, with destinationURL: URL) throws {
    #if os(WASI)
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destinationURL.path) {
        do {
            try fileManager.removeItem(at: destinationURL)
        } catch {
            throw ByteSinkError.fileReplaceFailure(error.localizedDescription)
        }
    }
    do {
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    } catch {
        throw ByteSinkError.fileReplaceFailure(error.localizedDescription)
    }
    #else
    guard DarwinBridge.rename(temporaryURL.path, destinationURL.path) == 0 else {
        throw ByteSinkError.fileReplaceFailure(String(cString: strerror(errno)))
    }
    #endif
}
