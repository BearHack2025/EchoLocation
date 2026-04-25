import ARKit
import CoreVideo
import Foundation

final class DepthAnalyzer {
  private let labelTrigger: GemmaLabelTrigger

  init(labelTrigger: GemmaLabelTrigger) {
    self.labelTrigger = labelTrigger
  }

  /// Last N raw direction picks. Used to smooth out 1-frame flips so the UI arrow
  /// doesn't jitter. Smoothing applies to direction ONLY — distance + label stay
  /// raw so the heatmap and pill react instantly to proximity changes.
  private var directionHistory: [String] = []
  private let historySize = 5

  /// If the spread between zones' stable distances is small (relative to the
  /// closest), the user is staring at a roughly flat surface — bias toward
  /// "center" instead of arbitrarily picking a peripheral edge.
  private let centerSimilarityRatio: Float = 0.15

  /// 30 s rolling tally of direction outputs. Emitted via NSLog so we can
  /// detect a relapse of the "always X" bias without re-instrumenting.
  private var directionCounts: [String: Int] = ["left": 0, "center": 0, "right": 0, "unknown": 0]
  private var lastDirectionReportAt = Date()
  private let directionReportInterval: TimeInterval = 30

  func analyze(frame: ARFrame, mode: String) -> [String: Any]? {
    guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
      return nil
    }

    let depthMap = depthData.depthMap
    guard let confidenceMap = depthData.confidenceMap else {
      return nil
    }

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
      CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    }

    // ------------------------------------------------------------------------
    // ORIENTATION CONVENTION
    // ------------------------------------------------------------------------
    // The depth map is in the camera's NATIVE LANDSCAPE orientation:
    //   `width`  = camera's long sensor axis  → vertical-on-screen in portrait
    //   `height` = camera's short sensor axis → horizontal-on-screen in portrait
    //
    // The app is locked to portrait (head/chest-mounted use case). To partition
    // L/C/R bands across the user's actual horizontal view, we split along the
    // `height` axis and iterate `width` inside each band. Treating `width` as
    // the partition axis (as we used to) silently maps L/C/R to top/center/
    // bottom of the user's view → "always right" bias.
    // ------------------------------------------------------------------------

    let nativeWidth = CVPixelBufferGetWidth(depthMap)    // portrait-vertical (iterated)
    let nativeHeight = CVPixelBufferGetHeight(depthMap)  // portrait-horizontal (partitioned)

    guard
      let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap),
      let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap)
    else {
      return nil
    }

    let depthPointer = depthBaseAddress.assumingMemoryBound(to: Float32.self)
    let confidencePointer = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)

    let rowStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
    let confidenceRowStride = CVPixelBufferGetBytesPerRow(confidenceMap)

    // 25 / 50 / 25 split along the portrait-horizontal axis (`nativeHeight`).
    // Center is twice the size of the peripheral bands so flat-front cases
    // bias toward "center" rather than picking an arbitrary edge.
    let leftBand   = max(1, nativeHeight / 4)
    let centerBand = max(1, nativeHeight / 2)
    let rightBand  = max(1, nativeHeight - leftBand - centerBand)

    let zones: [(String, Int, Int)] = [
      ("left",   0,                       leftBand),
      ("center", leftBand,                centerBand),
      ("right",  leftBand + centerBand,   rightBand)
    ]

    var results: [(direction: String, distance: Float, confidence: Double)] = []

    for (direction, startY, zoneHeight) in zones {
      guard zoneHeight > 0 else {
        continue
      }

      var samples: [Float] = []
      var confidenceHits = 0
      var totalHits = 0

      let yEnd = min(nativeHeight, startY + zoneHeight)
      let yStride = max(1, zoneHeight / 16)
      let xStride = max(1, nativeWidth / 24)

      for y in stride(from: startY, to: yEnd, by: yStride) {
        for x in stride(from: 0, to: nativeWidth, by: xStride) {
          let depthIndex = y * rowStride + x
          let confidenceIndex = y * confidenceRowStride + x

          let depthValue = depthPointer[depthIndex]
          let confidenceValue = confidencePointer[confidenceIndex]

          guard depthValue.isFinite, depthValue > 0.05, depthValue < 5.0 else {
            continue
          }

          totalHits += 1

          guard confidenceValue >= 1 else {
            continue
          }

          confidenceHits += 1
          samples.append(depthValue)
        }
      }

      guard !samples.isEmpty, totalHits > 0 else {
        continue
      }

      samples.sort()
      let stableIndex = min(samples.count - 1, max(0, samples.count / 5))
      let stableDistance = samples[stableIndex]
      let zoneConfidence = Double(confidenceHits) / Double(totalHits)
      results.append((direction: direction, distance: stableDistance, confidence: zoneConfidence))
    }

    guard !results.isEmpty else {
      return nil
    }

    let chosen = pickDirection(from: results)
    let smoothedDirection = smooth(direction: chosen.direction)
    tallyDirection(smoothedDirection)
    // Gemma-first label with MeshClassifier fallback. Trigger fires on
    // significant change; reads are O(1) and never block the AR queue.
    let label = labelTrigger.currentLabel(
      distance: Double(chosen.distance),
      direction: smoothedDirection,
      frame: frame
    )

    return [
      "nearestDistanceMeters": Double(chosen.distance),
      "direction": smoothedDirection,
      "label": label,
      "confidence": chosen.confidence,
      "mode": mode,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
      "source": "arkit"
    ]
  }

  // MARK: - Private

  /// Pick the active direction. If all zones report similar distances (the user
  /// is facing a roughly flat surface), force "center" instead of letting an edge
  /// pixel win by a hair. Otherwise pick the closest zone — the original behavior.
  private func pickDirection(
    from results: [(direction: String, distance: Float, confidence: Double)]
  ) -> (direction: String, distance: Float, confidence: Double) {
    let minResult = results.min(by: { $0.distance < $1.distance })!
    let maxDistance = results.map(\.distance).max()!
    let spread = (maxDistance - minResult.distance) / max(minResult.distance, 0.001)

    if spread < centerSimilarityRatio,
       let center = results.first(where: { $0.direction == "center" }) {
      return center
    }
    return minResult
  }

  /// Rolling 30 s direction tally. One-shot debug log; comment out the call
  /// site in `analyze` when no longer needed.
  private func tallyDirection(_ d: String) {
    directionCounts[d, default: 0] += 1
    let now = Date()
    guard now.timeIntervalSince(lastDirectionReportAt) >= directionReportInterval else {
      return
    }
    let total = max(1, directionCounts.values.reduce(0, +))
    let pct: (String) -> Int = { dir in
      Int(Double(self.directionCounts[dir, default: 0]) / Double(total) * 100)
    }
    NSLog(
      "[EchoLidar] direction%% over %.0fs — left:%d center:%d right:%d unknown:%d (n=%d)",
      directionReportInterval,
      pct("left"),
      pct("center"),
      pct("right"),
      pct("unknown"),
      total
    )
    directionCounts = ["left": 0, "center": 0, "right": 0, "unknown": 0]
    lastDirectionReportAt = now
  }

  /// Majority vote over the last `historySize` raw directions.
  private func smooth(direction raw: String) -> String {
    directionHistory.append(raw)
    if directionHistory.count > historySize {
      directionHistory.removeFirst()
    }
    let counts = Dictionary(grouping: directionHistory, by: { $0 }).mapValues(\.count)
    return counts.max(by: { $0.value < $1.value })?.key ?? raw
  }
}
