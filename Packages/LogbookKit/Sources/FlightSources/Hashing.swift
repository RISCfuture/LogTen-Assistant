import CryptoKit
import Foundation

private let hexAlphabet = Array("0123456789abcdef")

extension Sequence<UInt8> {
  /// The bytes as lowercase hexadecimal.
  var hexString: String {
    var result = ""
    for byte in self {
      result.append(hexAlphabet[Int(byte >> 4)])
      result.append(hexAlphabet[Int(byte & 0x0F)])
    }
    return result
  }
}

/// The SHA-256 digest of some data as lowercase hexadecimal.
func sha256Hex(of data: Data) -> String {
  SHA256.hash(data: data).hexString
}

/// The SHA-256 digest of a file's contents as lowercase hexadecimal.
func sha256Hex(of file: URL) throws -> String {
  sha256Hex(of: try Data(contentsOf: file))
}
