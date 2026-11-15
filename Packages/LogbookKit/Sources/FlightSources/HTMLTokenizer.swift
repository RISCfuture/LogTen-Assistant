import Foundation

/// A token of an HTML document.
enum HTMLToken: Equatable {
  case start(name: String, attributes: [String: String])
  case end(name: String)
  case text(String)
}

/// A forgiving HTML tokenizer, enough to read the flight list in a saved FlySto page.
///
/// It lowercases tag and attribute names, decodes character references in text and attribute
/// values, skips comments and the contents of `script` and `style`, and never fails.
struct HTMLTokenizer {
  private static let opening = UInt8(ascii: "<")
  private static let closing = UInt8(ascii: ">")
  private static let slash = UInt8(ascii: "/")
  private static let equals = UInt8(ascii: "=")
  private static let rawTextElements: Set<String> = ["script", "style"]

  private static let namedEntities = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"
  ]

  private let bytes: [UInt8]
  private var position = 0

  init(_ html: String) {
    bytes = Array(html.utf8)
  }

  static func tokens(in html: String) -> [HTMLToken] {
    var tokenizer = Self(html)
    var tokens = [HTMLToken]()
    while let token = tokenizer.next() { tokens.append(token) }
    return tokens
  }

  static func decode(_ text: String) -> String {
    guard text.contains("&") else { return text }
    return text.replacing(#/&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);/#) { match in
      let body = String(match.output.1)
      if body.hasPrefix("#x"), let value = UInt32(body.dropFirst(2), radix: 16),
        let scalar = UnicodeScalar(value)
      {
        return String(Character(scalar))
      }
      if body.hasPrefix("#"), let value = UInt32(body.dropFirst()),
        let scalar = UnicodeScalar(value)
      {
        return String(Character(scalar))
      }
      return namedEntities[body] ?? String(match.output.0)
    }
  }

  private mutating func next() -> HTMLToken? {
    guard position < bytes.count else { return nil }
    if bytes[position] == Self.opening, let token = tag() { return token }
    return text() ?? next()
  }

  private mutating func text() -> HTMLToken? {
    let start = position
    position += 1
    while position < bytes.count, bytes[position] != Self.opening { position += 1 }
    return .text(Self.decode((String(bytes: bytes[start..<position], encoding: .utf8) ?? "")))
  }

  /// Reads a tag, comment or doctype at the current `<`; returns `nil`, leaving the position
  /// unchanged, if the `<` is only text.
  private mutating func tag() -> HTMLToken? {
    let start = position
    guard start + 1 < bytes.count else { return nil }
    if matches("<!--") {
      skip(past: "-->")
      return next()
    }
    let second = bytes[start + 1]
    if second == UInt8(ascii: "!") || second == UInt8(ascii: "?") {
      skip(past: ">")
      return next()
    }
    if second == Self.slash {
      position += 2
      let name = readName()
      skip(past: ">")
      return name.isEmpty ? next() : .end(name: name)
    }
    guard Character(UnicodeScalar(second)).isLetter else { return nil }
    position += 1
    let name = readName()
    let attributes = readAttributes()
    if Self.rawTextElements.contains(name) {
      skip(past: "</\(name)")
      skip(past: ">")
      return .start(name: name, attributes: attributes)
    }
    return .start(name: name, attributes: attributes)
  }

  private mutating func readName() -> String {
    let start = position
    while position < bytes.count, !isSpace(bytes[position]), bytes[position] != Self.closing,
      bytes[position] != Self.slash, bytes[position] != Self.opening
    {
      position += 1
    }
    return (String(bytes: bytes[start..<position], encoding: .utf8) ?? "").lowercased()
  }

  private mutating func readAttributes() -> [String: String] {
    var attributes = [String: String]()
    while position < bytes.count {
      skipSpaces()
      guard position < bytes.count else { break }
      if bytes[position] == Self.closing {
        position += 1
        break
      }
      if bytes[position] == Self.slash {
        position += 1
        continue
      }
      let name = readAttributeName()
      guard !name.isEmpty else {
        position += 1
        continue
      }
      skipSpaces()
      if position < bytes.count, bytes[position] == Self.equals {
        position += 1
        skipSpaces()
        attributes[name] = Self.decode(readAttributeValue())
      } else {
        attributes[name] = ""
      }
    }
    return attributes
  }

  private mutating func readAttributeName() -> String {
    let start = position
    while position < bytes.count, !isSpace(bytes[position]), bytes[position] != Self.equals,
      bytes[position] != Self.closing, bytes[position] != Self.slash
    {
      position += 1
    }
    return (String(bytes: bytes[start..<position], encoding: .utf8) ?? "").lowercased()
  }

  private mutating func readAttributeValue() -> String {
    guard position < bytes.count else { return "" }
    let quote = bytes[position]
    if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
      position += 1
      let start = position
      while position < bytes.count, bytes[position] != quote { position += 1 }
      let value = (String(bytes: bytes[start..<position], encoding: .utf8) ?? "")
      position = min(position + 1, bytes.count)
      return value
    }
    let start = position
    while position < bytes.count, !isSpace(bytes[position]), bytes[position] != Self.closing {
      position += 1
    }
    return (String(bytes: bytes[start..<position], encoding: .utf8) ?? "")
  }

  private func matches(_ literal: String) -> Bool {
    let literal = Array(literal.utf8)
    guard position + literal.count <= bytes.count else { return false }
    return bytes[position..<position + literal.count].elementsEqual(literal)
  }

  private mutating func skip(past literal: String) {
    let literal = Array(literal.utf8)
    while position < bytes.count {
      if matches((String(bytes: literal, encoding: .utf8) ?? "")) {
        position += literal.count
        return
      }
      position += 1
    }
  }

  private mutating func skipSpaces() {
    while position < bytes.count, isSpace(bytes[position]) { position += 1 }
  }

  private func isSpace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
  }
}
