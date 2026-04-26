import Foundation
import simd

struct OCRTextDetection {
  let text: String
  let normalizedText: String
  let worldPoint: SIMD3<Float>
  let distance: Float
  let bearing: String
}

final class OCRTextTracker {
  struct Entry {
    let key: String
    var text: String
    var normalizedText: String
    var worldPoint: SIMD3<Float>
    var distance: Float
    var bearing: String
    var sightings: Int
    var lastSeenFrame: Int
  }

  private var entries: [String: Entry] = [:]
  private var frameCounter: Int = 0

  private let evictAfterFrames = 90
  private let maxMatchDistanceMeters: Float = 0.8
  private let maxDistanceDeltaMeters: Float = 1.2
  private let minimumSightings = 3

  func tick() {
    frameCounter += 1
    entries = entries.filter { _, entry in
      frameCounter - entry.lastSeenFrame < evictAfterFrames
    }
  }

  func ingest(_ detections: [OCRTextDetection]) {
    for detection in detections {
      let key = "\(detection.bearing)|\(detection.normalizedText)"
      if var entry = entries[key] {
        entry.text = detection.text
        entry.normalizedText = detection.normalizedText
        entry.worldPoint = detection.worldPoint
        entry.distance = detection.distance
        entry.bearing = detection.bearing
        entry.sightings += 1
        entry.lastSeenFrame = frameCounter
        entries[key] = entry
      } else {
        entries[key] = Entry(
          key: key,
          text: detection.text,
          normalizedText: detection.normalizedText,
          worldPoint: detection.worldPoint,
          distance: detection.distance,
          bearing: detection.bearing,
          sightings: 1,
          lastSeenFrame: frameCounter
        )
      }
    }
  }

  func bestText(
    near worldPoint: SIMD3<Float>,
    bearing: String,
    distanceHint: Float
  ) -> Entry? {
    var exact: (entry: Entry, distance: Float)?
    for (_, entry) in entries {
      guard entry.sightings >= minimumSightings else { continue }
      let delta = simd_distance(entry.worldPoint, worldPoint)
      guard delta <= maxMatchDistanceMeters else { continue }
      if exact == nil || delta < exact!.distance || entry.sightings > exact!.entry.sightings {
        exact = (entry, delta)
      }
    }
    if let exact {
      return exact.entry
    }

    var fallback: (entry: Entry, distanceDelta: Float)?
    for (_, entry) in entries {
      guard entry.sightings >= minimumSightings else { continue }
      guard entry.bearing == bearing else { continue }
      let delta = abs(entry.distance - distanceHint)
      guard delta <= maxDistanceDeltaMeters else { continue }
      if fallback == nil || delta < fallback!.distanceDelta || entry.sightings > fallback!.entry.sightings {
        fallback = (entry, delta)
      }
    }
    return fallback?.entry
  }

  func reset() {
    entries.removeAll()
    frameCounter = 0
  }
}
