public import Foundation

/// A CRC-32 checksum, as used by ZIP and gzip.
enum CRC32 {
  private static let polynomial: UInt32 = 0xEDB8_8320
  private static let table: [UInt32] = (0..<256).map { index in
    (0..<8).reduce(UInt32(index)) { value, _ in
      value & 1 == 1 ? (value >> 1) ^ polynomial : value >> 1
    }
  }

  static func checksum(_ data: Data) -> UInt32 {
    ~data.reduce(~UInt32(0)) { crc, byte in
      table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
  }
}

/// Builds the ZIP archive FlySto's log-upload endpoint expects: one file, in a standard
/// (non-ZIP64) container.
public enum ZipArchive {
  private static let localHeaderSignature: UInt32 = 0x0403_4B50
  private static let centralHeaderSignature: UInt32 = 0x0201_4B50
  private static let endSignature: UInt32 = 0x0605_4B50
  private static let version: UInt16 = 20
  private static let utf8NameFlag: UInt16 = 0x0800
  private static let storedMethod: UInt16 = 0
  private static let dosDate: UInt16 = 0x0021  // 1980-01-01
  private static let dosTime: UInt16 = 0

  /**
   Wraps a file in a ZIP archive without compressing it.

   - Parameters:
     - name: The file's name inside the archive.
     - contents: The file's contents.
   - Throws: ``BuildError/tooLarge`` if the file is 4 GiB or larger.
   */
  public static func archive(name: String, contents: Data) throws -> Data {
    let nameBytes = Data(name.utf8)
    guard contents.count < Int(UInt32.max), nameBytes.count < Int(UInt16.max) else {
      throw BuildError.tooLarge
    }
    let checksum = CRC32.checksum(contents)
    let size = UInt32(contents.count)

    var archive = Data()
    archive.appendLE(localHeaderSignature)
    archive.appendLE(version)
    archive.appendLE(utf8NameFlag)
    archive.appendLE(storedMethod)
    archive.appendLE(dosTime)
    archive.appendLE(dosDate)
    archive.appendLE(checksum)
    archive.appendLE(size)
    archive.appendLE(size)
    archive.appendLE(UInt16(nameBytes.count))
    archive.appendLE(UInt16(0))
    archive.append(nameBytes)
    archive.append(contents)

    let directoryOffset = UInt32(archive.count)
    var directory = Data()
    directory.appendLE(centralHeaderSignature)
    directory.appendLE(version)
    directory.appendLE(version)
    directory.appendLE(utf8NameFlag)
    directory.appendLE(storedMethod)
    directory.appendLE(dosTime)
    directory.appendLE(dosDate)
    directory.appendLE(checksum)
    directory.appendLE(size)
    directory.appendLE(size)
    directory.appendLE(UInt16(nameBytes.count))
    directory.appendLE(UInt16(0))  // extra field length
    directory.appendLE(UInt16(0))  // comment length
    directory.appendLE(UInt16(0))  // disk number
    directory.appendLE(UInt16(0))  // internal attributes
    directory.appendLE(UInt32(0))  // external attributes
    directory.appendLE(UInt32(0))  // local header offset
    directory.append(nameBytes)

    var end = Data()
    end.appendLE(endSignature)
    end.appendLE(UInt16(0))
    end.appendLE(UInt16(0))
    end.appendLE(UInt16(1))
    end.appendLE(UInt16(1))
    end.appendLE(UInt32(directory.count))
    end.appendLE(directoryOffset)
    end.appendLE(UInt16(0))

    return archive + directory + end
  }

  /// An error building an archive.
  public enum BuildError: Error, Equatable {
    /// The file or its name is too large for a standard ZIP container.
    case tooLarge
  }
}

extension Data {
  fileprivate mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
    Swift.withUnsafeBytes(of: value.littleEndian) { unsafe append(contentsOf: $0) }
  }
}
