public import LogbookModel

extension ICAOAddress {
  private static let firstUSAddress: UInt32 = 0xA0_0001
  private static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
  private static let maximumLength = 5
  private static let maximumSuffixLetters = 2

  /// Addresses taken by the one- and two-letter suffixes that can follow a prefix.
  private static let suffixBlock = UInt32(1 + letters.count * (1 + letters.count))

  /// Addresses taken by a prefix of four digits: itself, then one letter or one more digit.
  private static let fourDigitBlock = UInt32(1 + letters.count + 10)
  /// Addresses taken by a prefix of three digits and everything that can follow it.
  private static let threeDigitBlock = suffixBlock + 10 * fourDigitBlock
  /// Addresses taken by a prefix of two digits and everything that can follow it.
  private static let twoDigitBlock = suffixBlock + 10 * threeDigitBlock
  /// Addresses taken by a prefix of one digit and everything that can follow it.
  private static let oneDigitBlock = suffixBlock + 10 * twoDigitBlock

  /// The block below each digit in the second, third and fourth positions.
  private static let digitBlocks = [twoDigitBlock, threeDigitBlock, fourDigitBlock]

  /**
   Derives the ICAO address the FAA assigns to a US registration.

   US addresses are allocated in registration order from `A00001` (N1) to `ADF7C7` (N99999),
   so the address can be computed from the N-number alone.

   - Parameter registration: An N-number, with or without the leading `N`, such as `N12345` or
     `N1AB`.
   - Returns: The address, or `nil` if the registration isn't a valid N-number.
   */
  public init?(usRegistration registration: String) {
    var characters = Array(registration.uppercased())
    if characters.first == "N" { characters.removeFirst() }
    guard let offset = Self.offset(of: characters) else { return nil }
    self.init(rawValue: Self.firstUSAddress + offset)
  }

  private static func offset(of characters: [Character]) -> UInt32? {
    guard (1...maximumLength).contains(characters.count), characters.allSatisfy(\.isASCII),
      let first = characters[0].wholeNumberValue, first > 0
    else { return nil }
    var offset = UInt32(first - 1) * oneDigitBlock

    for position in 1..<characters.count {
      let character = characters[position]
      if letters.contains(character) {
        guard let suffix = suffixOffset(Array(characters[position...]), position: position) else {
          return nil
        }
        return offset + suffix
      }
      guard let digit = character.wholeNumberValue else { return nil }
      offset += digitOffset(digit, position: position)
    }
    return offset
  }

  private static func digitOffset(_ digit: Int, position: Int) -> UInt32 {
    guard position <= digitBlocks.count else { return UInt32(1 + letters.count + digit) }
    return suffixBlock + UInt32(digit) * digitBlocks[position - 1]
  }

  private static func suffixOffset(_ suffix: [Character], position: Int) -> UInt32? {
    let indices = suffix.map { letters.firstIndex(of: $0) }
    guard indices.allSatisfy({ $0 != nil }), suffix.count <= maximumSuffixLetters else {
      return nil
    }
    let first = UInt32(indices[0]!)
    if position == maximumLength - 1 {
      return suffix.count == 1 ? 1 + first : nil
    }
    let second = suffix.count == 2 ? UInt32(indices[1]!) + 1 : 0
    return first * UInt32(letters.count + 1) + 1 + second
  }
}
