import ARKit
import CoreVideo
import Foundation
import simd

final class DepthAnalyzer {
  private let meshClassifier = MeshClassifier()
  private(set) var lastNearestWorldPoint: SIMD3<Float>?
  private(set) var lastNearestDistance: Float?

  func analyze(frame: ARFrame, mode: String, tracker: ObjectAnchorTracker? = nil) -> [String: Any]? {
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
    var bestNormX: Float = 0.5
    var bestNormY: Float = 0.5

    let zones = [
      ("left", 0, zoneWidth),
      ("center", zoneWidth, zoneWidth),
      ("right", zoneWidth * 2, width - (zoneWidth * 2))
    ]

    for (direction, startX, zonePixelWidth) in zones {
      guard zonePixelWidth > 0 else {
        continue
      }

      var samples: [(Float, Int, Int)] = []
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
          samples.append((depthValue, x, y))
        }
      }

      guard !samples.isEmpty, totalHits > 0 else {
        continue
      }

      samples.sort { $0.0 < $1.0 }
      let stableIndex = min(samples.count - 1, max(0, samples.count / 5))
      let (stableDistance, stableX, stableY) = samples[stableIndex]
      let zoneConfidence = Double(confidenceHits) / Double(totalHits)

      if bestDistance == nil || stableDistance < bestDistance! {
        bestDistance = stableDistance
        bestDirection = direction
        bestConfidence = zoneConfidence
        bestNormX = Float(stableX) / Float(width)
        bestNormY = Float(stableY) / Float(height)
      }
    }

    guard let bestDistance else {
      return nil
    }

    var label = meshClassifier.classify(frame: frame, direction: bestDirection, distance: bestDistance)
    var labelSource = "arkit-mesh"

    let worldPoint = unproject(
      camera: frame.camera,
      normX: bestNormX,
      normY: bestNormY,
      depth: bestDistance
    )
    lastNearestWorldPoint = worldPoint
    lastNearestDistance = bestDistance

    if let tracker, let match = tracker.bestLabel(near: worldPoint) {
      label = match.label
      labelSource = "mlkit"
    }

    return [
      "nearestDistanceMeters": Double(bestDistance),
      "direction": bestDirection,
      "label": label,
      "confidence": bestConfidence,
      "mode": mode,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
      "source": "arkit",
      "labelSource": labelSource
    ]
  }

  private func unproject(
    camera: ARCamera,
    normX: Float,
    normY: Float,
    depth: Float
  ) -> SIMD3<Float> {
    let cameraTransform = camera.transform
    let intrinsics = camera.intrinsics
    let imageRes = camera.imageResolution
    let fx = intrinsics[0][0]
    let fy = intrinsics[1][1]
    let cx = intrinsics[2][0]
    let cy = intrinsics[2][1]

    let pxX = normX * Float(imageRes.width)
    let pxY = normY * Float(imageRes.height)

    let xCam = (pxX - cx) / fx * depth
    let yCam = (pxY - cy) / fy * depth
    let zCam = -depth

    let camPoint = SIMD4<Float>(xCam, yCam, zCam, 1)
    let worldPoint = cameraTransform * camPoint
    return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
  }
}
