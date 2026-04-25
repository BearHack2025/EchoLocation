import ARKit
import CoreVideo
import Foundation

final class DepthAnalyzer {
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

    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)

    guard
      let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap),
      let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap)
    else {
      return nil
    }

    let depthPointer = depthBaseAddress.assumingMemoryBound(to: Float32.self)
    let confidencePointer = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)

    let zoneWidth = max(1, width / 3)
    let rowStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
    let confidenceRowStride = CVPixelBufferGetBytesPerRow(confidenceMap)

    var bestDirection = "unknown"
    var bestDistance: Float?
    var bestConfidence = 0.0

    let zones = [
      ("left", 0, zoneWidth),
      ("center", zoneWidth, zoneWidth),
      ("right", zoneWidth * 2, width - (zoneWidth * 2))
    ]

    for (direction, startX, zonePixelWidth) in zones {
      guard zonePixelWidth > 0 else {
        continue
      }

      var samples: [Float] = []
      var confidenceHits = 0
      var totalHits = 0

      let xEnd = min(width, startX + zonePixelWidth)
      let yStride = max(1, height / 24)
      let xStride = max(1, zonePixelWidth / 16)

      for y in stride(from: 0, to: height, by: yStride) {
        for x in stride(from: startX, to: xEnd, by: xStride) {
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

      if bestDistance == nil || stableDistance < bestDistance! {
        bestDistance = stableDistance
        bestDirection = direction
        bestConfidence = zoneConfidence
      }
    }

    guard let bestDistance else {
      return nil
    }

    return [
      "nearestDistanceMeters": Double(bestDistance),
      "direction": bestDirection,
      "label": "obstacle",
      "confidence": bestConfidence,
      "mode": mode,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
      "source": "arkit"
    ]
  }
}
