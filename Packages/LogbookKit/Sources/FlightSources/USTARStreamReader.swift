import Foundation

/// A member of a tar archive that a ``USTARStreamReader`` extracted.
struct USTAREntry: Equatable {
  /// The member's path, without a leading `./`.
  var name: String
  /// The byte offset of the member's header in the archive.
  var offset: Int
  /// The member's contents.
  var data: Data
}

/// Reads a tar archive as it streams in, extracting only the members a filter accepts.
///
/// Members the filter rejects are skipped without being buffered, so a multi-gigabyte archive
/// costs only the memory of the members wanted. The reader understands ustar headers, GNU
/// long names and pax `path` records, and stops at the end-of-archive marker.
struct USTARStreamReader {
  private static let blockSize = 512
  private static let nameRange = 0..<100
  private static let sizeRange = 124..<136
  private static let checksumRange = 148..<156
  private static let typeFlagIndex = 156
  private static let prefixRange = 345..<500
  private static let magicRange = 257..<262
  private static let largestMember = 512 * 1_024 * 1_024

  private let wants: (String) -> Bool
  private var buffer = Data()
  private var cursor = 0
  private var stage = Stage.header
  private var bytesBeforeBuffer = 0

  private var pendingName: String?

  /// Whether the end-of-archive marker has been read.
  var isFinished: Bool {
    if case .finished = stage { true } else { false }
  }

  private var available: Int { buffer.count - cursor }

  /// Creates a reader that extracts the members whose names the filter accepts.
  init(wants: @escaping (String) -> Bool) {
    self.wants = wants
  }

  private static func kind(of flag: UInt8, name: String, wants: (String) -> Bool) -> Kind {
    switch flag {
      case UInt8(ascii: "L"): .longName
      case UInt8(ascii: "x"): .paxHeader
      case UInt8(ascii: "0"), 0: wants(name) ? .extract : .skip
      default: .skip
    }
  }

  private static func name(in block: Data.SubSequence) -> String {
    let base = block.startIndex
    var name = text(block[(base + nameRange.lowerBound)..<(base + nameRange.upperBound)])
    let isUSTAR = block[(base + magicRange.lowerBound)..<(base + magicRange.upperBound)]
      .elementsEqual("ustar".utf8)
    if isUSTAR {
      let prefix = text(block[(base + prefixRange.lowerBound)..<(base + prefixRange.upperBound)])
      if !prefix.isEmpty { name = prefix + "/" + name }
    }
    return normalize(name)
  }

  private static func normalize(_ name: String) -> String {
    name.hasPrefix("./") ? String(name.dropFirst(2)) : name
  }

  private static func text(_ bytes: Data.SubSequence) -> String {
    (String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "")
  }

  /// Parses the size field, which is octal text or, for very large members, base-256.
  private static func size(in block: Data.SubSequence) -> Int? {
    let base = block.startIndex
    let field = block[(base + sizeRange.lowerBound)..<(base + sizeRange.upperBound)]
    if let first = field.first, first & 0x80 != 0 {
      let value = field.dropFirst().reduce(0) { $0 << 8 | Int($1) }
      return value >= 0 ? value : nil
    }
    let digits = (String(bytes: field.prefix { $0 != 0 && $0 != 0x20 }, encoding: .utf8) ?? "")
    return digits.isEmpty ? 0 : Int(digits, radix: 8)
  }

  /// Finds the `path` key in pax extended-header records of the form `<length> key=value\n`.
  private static func paxPath(in data: Data) -> String? {
    var rest = data[...]
    while !rest.isEmpty {
      guard let space = rest.firstIndex(of: UInt8(ascii: " ")),
        let length = Int((String(bytes: rest[rest.startIndex..<space], encoding: .utf8) ?? "")),
        length > 0, length <= rest.count
      else { return nil }
      let record = rest[(space + 1)..<(rest.startIndex + length)]
      rest = rest.dropFirst(length)
      let text = (String(bytes: record, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines)
      if text.hasPrefix("path=") { return String(text.dropFirst("path=".count)) }
    }
    return nil
  }

  /// Consumes the next chunk of the archive and returns the wanted members it completed.
  mutating func append(_ chunk: Data) throws -> [USTAREntry] {
    buffer.append(chunk)
    var entries = [USTAREntry]()
    while let entry = try step() { entries.append(entry) }
    compact()
    return entries
  }

  /// Advances one step, returning an extracted member when one completes. Sets `stage` and
  /// returns `nil` when more input is needed.
  private mutating func step() throws -> USTAREntry? {
    while true {
      switch stage {
        case .finished:
          return nil
        case .header:
          guard available >= Self.blockSize else { return nil }
          try readHeader()
        case .body(var member):
          let taken = min(available, member.remaining + member.padding)
          guard taken > 0 || member.remaining + member.padding == 0 else { return nil }
          let contentTaken = min(taken, member.remaining)
          if member.kind != .skip {
            member.contents.append(
              buffer[(buffer.startIndex + cursor)..<(buffer.startIndex + cursor + contentTaken)]
            )
          }
          cursor += taken
          member.remaining -= contentTaken
          member.padding -= taken - contentTaken
          guard member.remaining == 0, member.padding == 0 else {
            stage = .body(member)
            return nil
          }
          stage = .header
          if let entry = finish(member) { return entry }
      }
    }
  }

  private mutating func compact() {
    guard cursor > 0 else { return }
    bytesBeforeBuffer += cursor
    buffer = Data(buffer[(buffer.startIndex + cursor)...])
    cursor = 0
  }

  private mutating func readHeader() throws {
    let offset = bytesBeforeBuffer + cursor
    let start = buffer.startIndex + cursor
    let block = buffer[start..<(start + Self.blockSize)]
    cursor += Self.blockSize
    if block.allSatisfy({ $0 == 0 }) {
      stage = .finished
      return
    }
    guard checksumMatches(block), let size = Self.size(in: block) else {
      throw ReadError.malformedHeader(offset: offset)
    }
    let flag = block[block.startIndex + Self.typeFlagIndex]
    let name = pendingName ?? Self.name(in: block)
    let kind = Self.kind(of: flag, name: name, wants: wants)
    if kind == .extract || kind == .skip { pendingName = nil }
    if kind == .extract, size > Self.largestMember { throw ReadError.memberTooLarge(name: name) }
    let padding = (Self.blockSize - size % Self.blockSize) % Self.blockSize
    stage = .body(Member(name: name, offset: offset, remaining: size, padding: padding, kind: kind))
  }

  private mutating func finish(_ member: Member) -> USTAREntry? {
    switch member.kind {
      case .extract:
        return USTAREntry(name: member.name, offset: member.offset, data: member.contents)
      case .longName:
        pendingName = Self.normalize(
          (String(bytes: member.contents.prefix { $0 != 0 }, encoding: .utf8) ?? "")
        )
      case .paxHeader:
        pendingName = Self.paxPath(in: member.contents).map(Self.normalize) ?? pendingName
      case .skip:
        break
    }
    return nil
  }

  private func checksumMatches(_ block: Data.SubSequence) -> Bool {
    let base = block.startIndex
    let stored = block[
      (base + Self.checksumRange.lowerBound)..<(base + Self.checksumRange.upperBound)
    ]
    let octalDigits = stored.filter { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "7") }
    let digits = String(bytes: octalDigits, encoding: .utf8) ?? ""
    guard let expected = Int(digits, radix: 8) else { return false }
    let space = Int(UInt8(ascii: " "))
    var sum = 0
    for (index, byte) in block.enumerated() {
      sum += Self.checksumRange.contains(index) ? space : Int(byte)
    }
    return sum == expected
  }

  enum ReadError: Error, Equatable {
    case malformedHeader(offset: Int)
    case memberTooLarge(name: String)
  }

  private enum Stage {
    case header
    case body(Member)
    case finished
  }

  private struct Member {
    var name: String
    var offset: Int
    var remaining: Int
    var padding: Int
    var kind: Kind
    var contents = Data()
  }

  private enum Kind {
    case extract
    case skip
    case longName
    case paxHeader
  }
}
