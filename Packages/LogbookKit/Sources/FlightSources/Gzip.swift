import Foundation

/// Decompresses gzip data (RFC 1952) holding a single member.
enum Gzip {
  private static let magic: [UInt8] = [0x1F, 0x8B]
  private static let deflateMethod: UInt8 = 8
  private static let fixedHeaderLength = 10
  private static let trailerLength = 8
  private static let hasHeaderCRC: UInt8 = 0x02
  private static let hasExtra: UInt8 = 0x04
  private static let hasName: UInt8 = 0x08
  private static let hasComment: UInt8 = 0x10

  static func isGzip(_ data: Data) -> Bool {
    data.starts(with: magic)
  }

  /// Returns the decompressed contents, verifying the length and CRC-32 in the trailer.
  static func decompress(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    guard bytes.starts(with: magic), bytes.count > 2, bytes[2] == deflateMethod else {
      throw DecodeError.notGzip
    }
    guard bytes.count >= fixedHeaderLength + trailerLength else { throw DecodeError.truncated }
    let payloadStart = try headerEnd(of: bytes)
    guard payloadStart <= bytes.count - trailerLength else { throw DecodeError.truncated }
    let deflated = Data(bytes[payloadStart..<(bytes.count - trailerLength)])
    let inflated: Data
    do {
      // NSData offers the only one-shot raw-DEFLATE decompression in Foundation.
      // swiftlint:disable:next legacy_objc_type
      inflated = try (deflated as NSData).decompressed(using: .zlib) as Data
    } catch {
      throw DecodeError.corrupt
    }
    let trailer = bytes.suffix(trailerLength)
    guard littleEndianUInt32(trailer.prefix(4)) == CRC32.checksum(inflated),
      littleEndianUInt32(trailer.suffix(4)) == UInt32(truncatingIfNeeded: inflated.count)
    else {
      throw DecodeError.corrupt
    }
    return inflated
  }

  private static func headerEnd(of bytes: [UInt8]) throws -> Int {
    let flags = bytes[3]
    var position = fixedHeaderLength
    if flags & hasExtra != 0 {
      guard position + 2 <= bytes.count else { throw DecodeError.truncated }
      let extraLength = Int(bytes[position]) | (Int(bytes[position + 1]) << 8)
      position += 2 + extraLength
    }
    for flag in [hasName, hasComment] where flags & flag != 0 {
      guard let end = bytes[min(position, bytes.count)...].firstIndex(of: 0) else {
        throw DecodeError.truncated
      }
      position = end + 1
    }
    if flags & hasHeaderCRC != 0 { position += 2 }
    return position
  }

  private static func littleEndianUInt32(_ bytes: some Collection<UInt8>) -> UInt32 {
    bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) }
  }

  enum DecodeError: Error, Equatable {
    case notGzip
    case truncated
    case corrupt
  }
}
