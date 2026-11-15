/// The similarity ratio of two strings as Python's `difflib.SequenceMatcher(None, a, b).ratio()`
/// computes it, including its automatic junk heuristic, so duplicate detection draws the line
/// where cleanup-logten does.
enum TextSimilarity {
  private static let autojunkMinimumLength = 200
  private static let autojunkPopularityDivisor = 100

  /// Twice the number of matching characters divided by the total length: 1 for identical
  /// strings, 0 for strings with nothing in common.
  static func ratio(_ first: String, _ second: String) -> Double {
    let a = Array(first.unicodeScalars)
    let b = Array(second.unicodeScalars)
    guard !a.isEmpty || !b.isEmpty else { return 1 }
    let matches = Matcher(a: a, b: b).matchingCharacterCount()
    return 2 * Double(matches) / Double(a.count + b.count)
  }

  private struct Matcher {
    let a: [Unicode.Scalar]
    let b: [Unicode.Scalar]
    let positionsInB: [Unicode.Scalar: [Int]]

    init(a: [Unicode.Scalar], b: [Unicode.Scalar]) {
      self.a = a
      self.b = b
      var positions = [Unicode.Scalar: [Int]]()
      for (index, scalar) in b.enumerated() { positions[scalar, default: []].append(index) }
      if b.count >= TextSimilarity.autojunkMinimumLength {
        let limit = b.count / TextSimilarity.autojunkPopularityDivisor + 1
        positions = positions.filter { $0.value.count <= limit }
      }
      positionsInB = positions
    }

    func matchingCharacterCount() -> Int {
      var total = 0
      var queue = [(a.startIndex, a.endIndex, b.startIndex, b.endIndex)]
      while let (aLow, aHigh, bLow, bHigh) = queue.popLast() {
        let (i, j, size) = longestMatch(aLow, aHigh, bLow, bHigh)
        guard size > 0 else { continue }
        total += size
        if aLow < i && bLow < j { queue.append((aLow, i, bLow, j)) }
        if i + size < aHigh && j + size < bHigh {
          queue.append((i + size, aHigh, j + size, bHigh))
        }
      }
      return total
    }

    private func longestMatch(_ aLow: Int, _ aHigh: Int, _ bLow: Int, _ bHigh: Int)
      -> (Int, Int, Int)
    {
      var (bestI, bestJ, bestSize) = (aLow, bLow, 0)
      var lengths = [Int: Int]()
      for i in aLow..<aHigh {
        var next = [Int: Int]()
        for j in positionsInB[a[i]] ?? [] {
          if j < bLow { continue }
          if j >= bHigh { break }
          let length = (lengths[j - 1] ?? 0) + 1
          next[j] = length
          if length > bestSize {
            (bestI, bestJ, bestSize) = (i - length + 1, j - length + 1, length)
          }
        }
        lengths = next
      }
      while bestI > aLow && bestJ > bLow && a[bestI - 1] == b[bestJ - 1] {
        (bestI, bestJ, bestSize) = (bestI - 1, bestJ - 1, bestSize + 1)
      }
      while bestI + bestSize < aHigh && bestJ + bestSize < bHigh
        && a[bestI + bestSize] == b[bestJ + bestSize]
      {
        bestSize += 1
      }
      return (bestI, bestJ, bestSize)
    }
  }
}
