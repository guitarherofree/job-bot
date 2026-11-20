import Foundation

/// Minimal ZIP support for DOCX files: writing (stored, uncompressed entries) and reading
/// (stored and deflated entries).
public enum Zip {
    public struct Entry {
        public var name: String
        public var data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    // MARK: Writing

    public static func archive(_ entries: [Entry], date: Date = Date()) -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(date)
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(out.count)
            // Local file header
            out.appendLE(UInt32(0x04034b50))
            out.appendLE(UInt16(20))          // version needed
            out.appendLE(UInt16(0x0800))      // flags: UTF-8 names
            out.appendLE(UInt16(0))           // method: stored
            out.appendLE(dosTime)
            out.appendLE(dosDate)
            out.appendLE(crc)
            out.appendLE(UInt32(entry.data.count))
            out.appendLE(UInt32(entry.data.count))
            out.appendLE(UInt16(nameData.count))
            out.appendLE(UInt16(0))           // extra length
            out.append(nameData)
            out.append(entry.data)
            // Central directory record
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))      // version made by
            central.appendLE(UInt16(20))      // version needed
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))       // extra
            central.appendLE(UInt16(0))       // comment
            central.appendLE(UInt16(0))       // disk number
            central.appendLE(UInt16(0))       // internal attributes
            central.appendLE(UInt32(0))       // external attributes
            central.appendLE(offset)
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        // End of central directory
        out.appendLE(UInt32(0x06054b50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(central.count))
        out.appendLE(centralOffset)
        out.appendLE(UInt16(0))
        return out
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour: Int = c.hour ?? 0
        let minute: Int = c.minute ?? 0
        let second: Int = c.second ?? 0
        let year: Int = max(0, (c.year ?? 1980) - 1980)
        let month: Int = c.month ?? 1
        let dayOfMonth: Int = c.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | (second / 2)
        let day: Int = (year << 9) | (month << 5) | dayOfMonth
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: day))
    }

    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: Reading

    public enum ReadError: Error, LocalizedError {
        case notAZip
        case unsupported(String)
        case damaged

        public var errorDescription: String? {
            switch self {
            case .notAZip: return "The file isn't a valid Word document (it isn't a ZIP package)."
            case .unsupported(let what): return "The Word document uses a format Job Bot can't read (\(what))."
            case .damaged: return "The Word document seems to be damaged."
            }
        }
    }

    /// Reads one entry by name.
    public static func read(_ name: String, from archive: Data) throws -> Data? {
        let bytes = [UInt8](archive)
        guard bytes.count >= 22 else { throw ReadError.notAZip }
        // Find the end-of-central-directory record.
        var eocd = -1
        var i = bytes.count - 22
        let limit = max(0, bytes.count - 22 - 65535)
        while i >= limit {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ReadError.notAZip }
        let count = Int(u16(bytes, eocd + 10))
        var p = Int(u32(bytes, eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014b50 else { throw ReadError.damaged }
            let method = u16(bytes, p + 10)
            let compressedSize = Int(u32(bytes, p + 20))
            let size = Int(u32(bytes, p + 24))
            let nameLength = Int(u16(bytes, p + 28))
            let extraLength = Int(u16(bytes, p + 30))
            let commentLength = Int(u16(bytes, p + 32))
            let localOffset = Int(u32(bytes, p + 42))
            guard p + 46 + nameLength <= bytes.count else { throw ReadError.damaged }
            let entryName = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            p += 46 + nameLength + extraLength + commentLength
            guard entryName == name else { continue }
            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x04034b50 else { throw ReadError.damaged }
            let start = localOffset + 30 + Int(u16(bytes, localOffset + 26)) + Int(u16(bytes, localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ReadError.damaged }
            let payload = Data(bytes[start..<(start + compressedSize)])
            switch method {
            case 0: return payload
            case 8: return try inflate(payload, expectedSize: size)
            default: throw ReadError.unsupported("compression method \(method)")
            }
        }
        return nil
    }

    static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        #if canImport(Darwin)
        // Apple's "zlib" algorithm is raw DEFLATE, which is what ZIP uses.
        do {
            let out = try (data as NSData).decompressed(using: .zlib) as Data
            return out
        } catch {
            throw ReadError.damaged
        }
        #else
        throw ReadError.unsupported("compressed entries on this platform")
        #endif
    }

    static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        let lo = UInt16(b[i])
        let hi = UInt16(b[i + 1]) << 8
        return lo | hi
    }

    static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        var v = UInt32(b[i])
        v |= UInt32(b[i + 1]) << 8
        v |= UInt32(b[i + 2]) << 16
        v |= UInt32(b[i + 3]) << 24
        return v
    }
}

extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8(v >> 8))
    }

    mutating func appendLE(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}
