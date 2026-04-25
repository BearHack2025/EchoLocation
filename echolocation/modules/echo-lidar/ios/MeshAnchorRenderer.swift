import ARKit
import SceneKit
import UIKit

/// Builds wireframe SCNGeometry from ARMeshAnchors. Each anchor's geometry is
/// colored by the majority `ARMeshClassification` in its faces.
/// Wireframe via `material.fillMode = .lines` so we can see camera + structure.
enum MeshAnchorRenderer {
  // MARK: - Public

  /// Build a fresh SCNGeometry for a mesh anchor. Caller owns the SCNNode.
  static func makeGeometry(for anchor: ARMeshAnchor) -> SCNGeometry {
    let mesh = anchor.geometry

    let vertexSource = SCNGeometrySource(
      buffer: mesh.vertices.buffer,
      vertexFormat: mesh.vertices.format,
      semantic: .vertex,
      vertexCount: mesh.vertices.count,
      dataOffset: mesh.vertices.offset,
      dataStride: mesh.vertices.stride
    )

    // ARMeshGeometry.faces stores triangle vertex indices. SCNGeometryElement
    // consumes the same MTLBuffer.
    let element = SCNGeometryElement(
      buffer: mesh.faces.buffer,
      primitiveType: .triangles,
      primitiveCount: mesh.faces.count,
      bytesPerIndex: mesh.faces.bytesPerIndex
    )

    let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
    geometry.firstMaterial = makeWireframeMaterial(color: majorityColor(for: anchor))
    return geometry
  }

  // MARK: - Material

  private static func makeWireframeMaterial(color: UIColor) -> SCNMaterial {
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.fillMode = .lines
    mat.isDoubleSided = true
    mat.lightingModel = .constant
    mat.writesToDepthBuffer = false
    return mat
  }

  // MARK: - Classification → Color

  private static func majorityColor(for anchor: ARMeshAnchor) -> UIColor {
    color(for: majorityClassification(for: anchor))
  }

  private static func majorityClassification(for anchor: ARMeshAnchor) -> ARMeshClassification {
    let mesh = anchor.geometry
    guard let classificationSource = mesh.classification else {
      return .none
    }

    let faceCount = mesh.faces.count
    var counts: [ARMeshClassification: Int] = [:]
    let stride = classificationSource.stride
    let offset = classificationSource.offset
    let base = classificationSource.buffer.contents()

    // Sample every 4th face to keep this cheap on dense meshes.
    var i = 0
    while i < faceCount {
      let raw = base.advanced(by: offset + stride * i)
        .assumingMemoryBound(to: UInt8.self).pointee
      if let cls = ARMeshClassification(rawValue: Int(raw)) {
        counts[cls, default: 0] += 1
      }
      i += 4
    }

    return counts.max(by: { $0.value < $1.value })?.key ?? .none
  }

  /// Hackathon palette — distinct + readable on top of camera feed.
  static func color(for classification: ARMeshClassification) -> UIColor {
    switch classification {
    case .wall:    return UIColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 0.60)
    case .floor:   return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.40)
    case .ceiling: return UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 0.40)
    case .table:   return UIColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 0.60)
    case .seat:    return UIColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 0.60)
    case .door:    return UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 0.60)
    case .window:  return UIColor(red: 0.39, green: 0.82, blue: 1.00, alpha: 0.40)
    case .none:    fallthrough
    @unknown default:
      return UIColor(white: 1.0, alpha: 0.25)
    }
  }
}
