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
  private let evictAfterFrames = 30
  private let maxMatchDistanceMeters: Float = 0.3
  private let highConfidenceThreshold: Float = 0.7

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

  /// Best label near a given world point, or nil if no high-confidence match.
  func bestLabel(near worldPoint: SIMD3<Float>) -> (label: String, confidence: Float)? {
    var best: (entry: Entry, dist: Float)?
    for (_, entry) in entries {
      let d = simd_distance(entry.worldPoint, worldPoint)
      if d < maxMatchDistanceMeters {
        if best == nil || d < best!.dist {
          best = (entry, d)
        }
      }
    }
    guard let chosen = best?.entry else { return nil }

    // Most-frequent label across recent frames, with averaged confidence.
    var freq: [String: Int] = [:]
    var confSum: [String: Float] = [:]
    for (i, label) in chosen.labelHistory.enumerated() {
      freq[label, default: 0] += 1
      confSum[label, default: 0] += chosen.confidenceHistory[i]
    }
    guard let topLabel = freq.max(by: { $0.value < $1.value })?.key else { return nil }
    let avgConf = (confSum[topLabel] ?? 0) / Float(freq[topLabel] ?? 1)

    if avgConf < highConfidenceThreshold {
      return nil
    }
    return (topLabel, avgConf)
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
