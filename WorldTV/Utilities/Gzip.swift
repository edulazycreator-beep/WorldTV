import Compression
import Foundation

enum GzipError: LocalizedError {
    case invalidHeader
    case corrupt

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "The compressed file has an invalid gzip header."
        case .corrupt: return "The compressed file is corrupt."
        }
    }
}

/// Minimal gzip (RFC 1952) decoder built on Apple's Compression framework,
/// used for `.xml.gz` programme guides.
enum Gzip {
    static func isGzipped(_ data: Data) -> Bool {
        data.count > 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw GzipError.invalidHeader
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw GzipError.invalidHeader }
            let length = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + length
        }
        if flags & 0x08 != 0 { offset = skipZeroTerminated(bytes, from: offset) } // FNAME
        if flags & 0x10 != 0 { offset = skipZeroTerminated(bytes, from: offset) } // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset < bytes.count - 8 else { throw GzipError.invalidHeader }
        return try inflate(Array(bytes[offset..<(bytes.count - 8)]))
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        return index + 1
    }

    /// Inflates a raw DEFLATE stream (COMPRESSION_ZLIB is raw DEFLATE on Apple platforms).
    static func inflate(_ input: [UInt8]) throws -> Data {
        guard !input.isEmpty else { return Data() }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GzipError.corrupt
        }
        defer { compression_stream_destroy(stream) }

        let bufferSize = 256 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var output = Data()

        try input.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
            stream.pointee.dst_ptr = buffer
            stream.pointee.dst_size = bufferSize

            var status = COMPRESSION_STATUS_OK
            repeat {
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
                    throw GzipError.corrupt
                }
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 { output.append(buffer, count: produced) }
                if status == COMPRESSION_STATUS_OK, produced == 0, stream.pointee.src_size == 0 {
                    throw GzipError.corrupt // no progress possible
                }
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
            } while status == COMPRESSION_STATUS_OK
        }
        return output
    }
}
