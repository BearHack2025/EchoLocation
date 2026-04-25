import Foundation

/// Parses the two-line scene-description output:
/// LINE 1: short sentence
/// LINE 2: comma-separated objects
///
/// Robust to extra whitespace, missing line 2, or model preamble before the lines.
enum SceneOutputParser {
  struct Result {
    let sentence: String
    let objects: [String]
  }

  static func parse(_ raw: String) -> Result {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = trimmed
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    let sentence = lines.first ?? trimmed
    let objects: [String]
    if lines.count >= 2 {
      objects = lines[1]
        .components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
        .uniqued()
    } else {
      objects = []
    }

    return Result(sentence: sentence, objects: objects)
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
