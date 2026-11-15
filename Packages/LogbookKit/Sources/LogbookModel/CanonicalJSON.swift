import CryptoKit
import Foundation

/// Serializes JSON values byte-for-byte as Python's
/// `json.dumps(value, sort_keys=True, separators=(",", ":"))` does.
///
/// Content-addressed identifiers hash this form, so identifiers computed here match those the
/// cleanup-logten tool computed for the same rule, records and evidence. Object keys sort by
/// Unicode code point, non-ASCII characters are escaped as `\uXXXX` (with surrogate pairs), and
/// floating-point numbers use the shortest round-tripping representation.
public enum CanonicalJSON {
  private static let hexDigits = Array("0123456789abcdef")

  /// Returns the canonical serialization of a value.
  public static func string(for value: JSONValue) -> String {
    var output = ""
    append(value, to: &output)
    return output
  }

  /// Returns the lowercase hexadecimal SHA-256 digest of a value's canonical serialization.
  public static func sha256(of value: JSONValue) -> String {
    let digest = SHA256.hash(data: Data(string(for: value).utf8))
    return digest.map { byte in
      String([hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]])
    }
    .joined()
  }

  private static func append(_ value: JSONValue, to output: inout String) {
    switch value {
      case .null: output += "null"
      case .bool(let value): output += value ? "true" : "false"
      case .integer(let value): output += String(value)
      case .double(let value): output += number(value)
      case .string(let value): appendString(value, to: &output)
      case .array(let elements):
        output += "["
        for (index, element) in elements.enumerated() {
          if index > 0 { output += "," }
          append(element, to: &output)
        }
        output += "]"
      case .object(let members):
        output += "{"
        let keys = members.keys.sorted {
          $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
        }
        for (index, key) in keys.enumerated() {
          if index > 0 { output += "," }
          appendString(key, to: &output)
          output += ":"
          append(members[key]!, to: &output)
        }
        output += "}"
    }
  }

  private static func number(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    return value.description
  }

  private static func appendString(_ string: String, to output: inout String) {
    output += "\""
    for scalar in string.unicodeScalars {
      switch scalar {
        case "\"": output += "\\\""
        case "\\": output += "\\\\"
        case "\n": output += "\\n"
        case "\r": output += "\\r"
        case "\t": output += "\\t"
        case "\u{08}": output += "\\b"
        case "\u{0C}": output += "\\f"
        case " "..."~": output.unicodeScalars.append(scalar)
        default:
          for unit in String(scalar).utf16 { appendEscape(unit, to: &output) }
      }
    }
    output += "\""
  }

  private static func appendEscape(_ unit: UInt16, to output: inout String) {
    output += "\\u"
    for shift in stride(from: 12, through: 0, by: -4) {
      output.append(hexDigits[Int((unit >> UInt16(shift)) & 0x0F)])
    }
  }
}
