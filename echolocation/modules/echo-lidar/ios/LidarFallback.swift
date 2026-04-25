import Foundation

/// Deterministic fallback when Gemma fails / times out / produces unparseable output.
/// Builds a result with the same shape as a successful Gemma direction call so the
/// JS orchestrator can branch on `source` without changing the surface.
enum LidarFallback {
  struct Context {
    let distanceM: Double?
    let lidarDirection: String      // "left" | "center" | "right" | "unknown"
    let lidarLabel: String          // "wall" | "floor" | ...
  }

  struct Result {
    let direction: String           // "left" | "forward" | "right" | "stop"
    let confidence: Double          // 0..1, soft signal
    let reason: String
    let sentence: String
    let source: String              // always "lidar-fallback"
  }

  static func makeDirectionResult(_ ctx: Context) -> Result {
    // Hard stop if the obstacle is right in front of the user.
    if let d = ctx.distanceM, d < 0.6 {
      return Result(
        direction: "stop",
        confidence: 0.9,
        reason: "very close obstacle",
        sentence: "Stop. Obstacle very close \(directionPhrase(ctx.lidarDirection)).",
        source: "lidar-fallback"
      )
    }

    let direction: String
    switch ctx.lidarDirection {
    case "left":   direction = "right"   // threat on left → guide right
    case "right":  direction = "left"
    case "center": direction = "stop"
    default:       direction = "forward"
    }

    let distanceText = ctx.distanceM.map { "\(formatMeters($0)) ahead" } ?? "nearby"
    let sentence = "\(ctx.lidarLabel.capitalized) \(directionPhrase(ctx.lidarDirection)), \(distanceText). Try \(direction)."
    return Result(
      direction: direction,
      confidence: 0.5,
      reason: "lidar heuristic",
      sentence: sentence,
      source: "lidar-fallback"
    )
  }

  static func makeSceneSentence(_ ctx: Context) -> String {
    let dir = directionPhrase(ctx.lidarDirection)
    let dist = ctx.distanceM.map { ", \(formatMeters($0))" } ?? ""
    return "\(ctx.lidarLabel.capitalized) \(dir)\(dist)."
  }

  // MARK: - Private

  private static func directionPhrase(_ dir: String) -> String {
    switch dir {
    case "center": return "ahead"
    case "left":   return "to your left"
    case "right":  return "to your right"
    default:       return "nearby"
    }
  }

  private static func formatMeters(_ m: Double) -> String {
    if m < 1 { return "very close" }
    if m < 2 { return String(format: "%.1f meters", m) }
    return "\(Int(m.rounded())) meters"
  }
}
