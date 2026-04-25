import Foundation

/// Parses the structured JSON direction output. The model is told to emit a single
/// JSON object on one line. We tolerate code fences, leading prose, and trailing
/// noise by locating the first `{` and matching `}`.
enum DirectionOutputParser {
  struct Decoded: Codable {
    let direction: String
    let confidence: Double?
    let reason: String?
    let sentence: String
  }

  enum Direction: String {
    case left, forward, right, stop
  }

  struct Result {
    let direction: Direction
    let confidence: Double
    let reason: String
    let sentence: String
  }

  static func parse(_ raw: String) -> Result? {
    guard let json = extractJSONObject(from: raw) else { return nil }
    guard let data = json.data(using: .utf8) else { return nil }
    guard let decoded = try? JSONDecoder().decode(Decoded.self, from: data) else { return nil }
    guard let dir = Direction(rawValue: decoded.direction.lowercased()) else { return nil }
    let conf = max(0, min(1, decoded.confidence ?? 0.5))
    return Result(
      direction: dir,
      confidence: conf,
      reason: decoded.reason ?? "",
      sentence: decoded.sentence
    )
  }

  private static func extractJSONObject(from raw: String) -> String? {
    guard let openIdx = raw.firstIndex(of: "{") else { return nil }
    var depth = 0
    var i = openIdx
    while i < raw.endIndex {
      let c = raw[i]
      if c == "{" { depth += 1 }
      if c == "}" {
        depth -= 1
        if depth == 0 {
          let next = raw.index(after: i)
          return String(raw[openIdx..<next])
        }
      }
      i = raw.index(after: i)
    }
    return nil
  }
}
