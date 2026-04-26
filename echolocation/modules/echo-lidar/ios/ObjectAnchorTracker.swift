import Foundation
import simd

struct MLKitDetection {
  let trackingID: Int
  let label: String
  let confidence: Float
  let worldPoint: SIMD3<Float>
  let distance: Float
  let bearing: String
}

/// Stores per-tracked-object label history + last-seen world point.
/// Enables smoothing across frames and "what label is near this 3D point?" queries.
final class ObjectAnchorTracker {
  struct Entry {
    let trackingID: Int
    var worldPoint: SIMD3<Float>
    var distance: Float
    var bearing: String
    var labelHistory: [String]
    var confidenceHistory: [Float]
    var lastSeenFrame: Int
  }

  private var entries: [Int: Entry] = [:]
  private var frameCounter: Int = 0

  // Eviction / fusion knobs.
  private let historySize = 6
  private let evictAfterFrames = 45
  private let maxMatchDistanceMeters: Float = 0.6
  private let maxDistanceDeltaMeters: Float = 1.0
  private let highConfidenceThreshold: Float = 0.45

  func tick() {
    frameCounter += 1
    entries = entries.filter { _, entry in
      frameCounter - entry.lastSeenFrame < evictAfterFrames
    }
  }

  func ingest(_ detections: [MLKitDetection]) {
    for d in detections {
      if var existing = entries[d.trackingID] {
        existing.worldPoint = d.worldPoint
        existing.distance = d.distance
        existing.bearing = d.bearing
        existing.labelHistory.append(d.label)
        existing.confidenceHistory.append(d.confidence)
        if existing.labelHistory.count > historySize {
          existing.labelHistory.removeFirst()
          existing.confidenceHistory.removeFirst()
        }
        existing.lastSeenFrame = frameCounter
        entries[d.trackingID] = existing
      } else {
        entries[d.trackingID] = Entry(
          trackingID: d.trackingID,
          worldPoint: d.worldPoint,
          distance: d.distance,
          bearing: d.bearing,
          labelHistory: [d.label],
          confidenceHistory: [d.confidence],
          lastSeenFrame: frameCounter
        )
      }
    }
  }

  /// Best label near a given world point, with a fallback that uses bearing and
  /// rough distance when the exact 3D point does not line up cleanly.
  func bestLabel(
    near worldPoint: SIMD3<Float>,
    bearing: String,
    distanceHint: Float
  ) -> (label: String, confidence: Float)? {
    var best: (entry: Entry, dist: Float)?
    for (_, entry) in entries {
      let d = simd_distance(entry.worldPoint, worldPoint)
      if d < maxMatchDistanceMeters {
        if best == nil || d < best!.dist {
          best = (entry, d)
        }
      }
    }

    if let chosen = best?.entry, let label = resolvedLabel(for: chosen) {
      return label
    }

    var fallback: (entry: Entry, distanceDelta: Float)?
    for (_, entry) in entries {
      guard entry.bearing == bearing else { continue }
      let distanceDelta = abs(entry.distance - distanceHint)
      guard distanceDelta <= maxDistanceDeltaMeters else { continue }
      if fallback == nil || distanceDelta < fallback!.distanceDelta {
        fallback = (entry, distanceDelta)
      }
    }

    guard let chosen = fallback?.entry else { return nil }
    return resolvedLabel(for: chosen)
  }

  private func resolvedLabel(for chosen: Entry) -> (label: String, confidence: Float)? {
    guard let topLabel = mostLikelyLabel(for: chosen) else { return nil }
    let avgConf = averageConfidence(for: topLabel, in: chosen)

    if avgConf < highConfidenceThreshold {
      return nil
    }
    return (topLabel, avgConf)
  }

  private func mostLikelyLabel(for chosen: Entry) -> String? {
    var freq: [String: Int] = [:]
    for label in chosen.labelHistory {
      freq[label, default: 0] += 1
    }
    return freq.max(by: { $0.value < $1.value })?.key
  }

  private func averageConfidence(for targetLabel: String, in chosen: Entry) -> Float {
    var confSum: Float = 0
    var count: Int = 0
    for (i, label) in chosen.labelHistory.enumerated() {
      if label == targetLabel {
        confSum += chosen.confidenceHistory[i]
        count += 1
      }
    }
    guard count > 0 else { return 0 }
    return confSum / Float(count)
  }

  /// All currently tracked labeled objects (for richer JS payloads if needed).
  func snapshot() -> [Entry] {
    return Array(entries.values)
  }

  func reset() {
    entries.removeAll()
    frameCounter = 0
  }
}
