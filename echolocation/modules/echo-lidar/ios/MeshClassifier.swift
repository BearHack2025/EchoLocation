import ARKit
import Foundation

final class MeshClassifier {
  // Smooth labels across frames to avoid jitter
  private var labelHistory: [String] = []
  private let historySize = 8

  func classify(frame: ARFrame, direction: String, distance: Float) -> String {
    let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
    guard !meshAnchors.isEmpty else { return "obstacle" }

    let cameraInverse = simd_inverse(frame.camera.transform)
    let (xMin, xMax) = zoneNormalizedXBounds(for: direction, camera: frame.camera)
    let distanceTolerance = max(0.5, distance * 0.5)

    var counts: [ARMeshClassification: Int] = [:]

    for anchor in meshAnchors {
      let geometry = anchor.geometry
      let faceCount = geometry.faces.count

      // Sample every other face for performance
      var faceIndex = 0
      while faceIndex < faceCount {
        let centroidWorld = faceCentroid(geometry: geometry, faceIndex: faceIndex, anchorTransform: anchor.transform)
        let cam = cameraInverse * SIMD4<Float>(centroidWorld, 1)

        // ARKit camera looks down -z; discard faces behind or too far
        guard cam.z < 0 else { faceIndex += 2; continue }
        let depth = -cam.z
        guard abs(depth - distance) < distanceTolerance else { faceIndex += 2; continue }

        // Normalized x = tan(horizontal angle); partition matches depth analyzer zones
        let nx = cam.x / depth
        guard nx >= xMin && nx <= xMax else { faceIndex += 2; continue }

        let label = faceClassification(geometry: geometry, faceIndex: faceIndex)
        if label != .none {
          counts[label, default: 0] += 1
        }

        faceIndex += 2
      }
    }

    let raw = counts.max(by: { $0.value < $1.value }).map { labelString($0.key) } ?? "obstacle"
    return smoothed(raw)
  }

  func reset() {
    labelHistory.removeAll()
  }

  // MARK: - Private

  private func faceClassification(geometry: ARMeshGeometry, faceIndex: Int) -> ARMeshClassification {
    guard let src = geometry.classification else { return .none }
    let raw = src.buffer.contents()
      .advanced(by: src.offset + src.stride * faceIndex)
      .assumingMemoryBound(to: UInt8.self).pointee
    return ARMeshClassification(rawValue: Int(raw)) ?? .none
  }

  private func faceCentroid(
    geometry: ARMeshGeometry,
    faceIndex: Int,
    anchorTransform: simd_float4x4
  ) -> SIMD3<Float> {
    let faces = geometry.faces
    let facePtr = faces.buffer.contents()
      .advanced(by: faces.bytesPerIndex * 3 * faceIndex)
      .assumingMemoryBound(to: UInt32.self)

    let i0 = Int(facePtr[0])
    let i1 = Int(facePtr[1])
    let i2 = Int(facePtr[2])

    let v0 = vertex(geometry: geometry, index: i0)
    let v1 = vertex(geometry: geometry, index: i1)
    let v2 = vertex(geometry: geometry, index: i2)

    let localCentroid = (v0 + v1 + v2) / 3
    let world = anchorTransform * SIMD4<Float>(localCentroid, 1)
    return SIMD3<Float>(world.x, world.y, world.z)
  }

  private func vertex(geometry: ARMeshGeometry, index: Int) -> SIMD3<Float> {
    let src = geometry.vertices
    let ptr = src.buffer.contents()
      .advanced(by: src.offset + src.stride * index)
      .assumingMemoryBound(to: SIMD3<Float>.self)
    return ptr.pointee
  }

  // Match the three equal-width pixel zones from DepthAnalyzer projected into normalized camera space.
  // Using the camera intrinsics: normalizedX = (pixelX - cx) / fx
  private func zoneNormalizedXBounds(for direction: String, camera: ARCamera) -> (Float, Float) {
    let intrinsics = camera.intrinsics
    let imageResolution = camera.imageResolution
    let fx = intrinsics[0][0]
    let cx = intrinsics[2][0]
    let width = Float(imageResolution.width)
    let third = width / 3

    let leftEdge  = (0       - cx) / fx
    let mid1      = (third   - cx) / fx
    let mid2      = (third*2 - cx) / fx
    let rightEdge = (width   - cx) / fx

    switch direction {
    case "left":   return (leftEdge, mid1)
    case "center": return (mid1, mid2)
    default:       return (mid2, rightEdge)
    }
  }

  private func smoothed(_ label: String) -> String {
    labelHistory.append(label)
    if labelHistory.count > historySize {
      labelHistory.removeFirst()
    }
    // Return the most frequent label in recent history
    var freq: [String: Int] = [:]
    for l in labelHistory { freq[l, default: 0] += 1 }
    return freq.max(by: { $0.value < $1.value })?.key ?? label
  }

  private func labelString(_ classification: ARMeshClassification) -> String {
    switch classification {
    case .wall:    return "wall"
    case .floor:   return "floor"
    case .ceiling: return "obstacle"
    case .table:   return "table"
    case .seat:    return "seat"
    case .window:  return "window"
    case .door:    return "door"
    default:       return "obstacle"
    }
  }
}
