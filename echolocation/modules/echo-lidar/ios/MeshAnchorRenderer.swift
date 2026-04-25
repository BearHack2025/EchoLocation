import ARKit
import SceneKit
import UIKit

/// Builds the two SCNGeometry layers we render per ARMeshAnchor:
/// - **fill**: solid faces, distance-shaded via `MeshDistanceShader`
/// - **outline**: same faces in `.lines` mode, classification-colored
///
/// Both share the underlying MTLBuffers — only materials differ.
enum MeshAnchorRenderer {
  // MARK: - Public

  /// Solid distance-shaded fill. Faces visible.
  static func makeFillGeometry(for anchor: ARMeshAnchor) -> SCNGeometry {
    let geometry = makeBaseGeometry(for: anchor)
    let material = SCNMaterial()
    MeshDistanceShader.applyHeatmap(to: material)
    geometry.firstMaterial = material
    return geometry
  }

  /// Wireframe outline colored by majority `ARMeshClassification` of the anchor.
  static func makeOutlineGeometry(for anchor: ARMeshAnchor) -> SCNGeometry {
    let geometry = makeBaseGeometry(for: anchor)
    geometry.firstMaterial = makeOutlineMaterial(color: majorityColor(for: anchor))
    return geometry
  }

  // MARK: - Geometry (shared)

  private static func makeBaseGeometry(for anchor: ARMeshAnchor) -> SCNGeometry {
    let mesh = anchor.geometry

    let vertexSource = SCNGeometrySource(
      buffer: mesh.vertices.buffer,
      vertexFormat: mesh.vertices.format,
      semantic: .vertex,
      vertexCount: mesh.vertices.count,
      dataOffset: mesh.vertices.offset,
      dataStride: mesh.vertices.stride
    )

    let element = SCNGeometryElement(
      buffer: mesh.faces.buffer,
      primitiveType: .triangles,
      primitiveCount: mesh.faces.count,
      bytesPerIndex: mesh.faces.bytesPerIndex
    )

    return SCNGeometry(sources: [vertexSource], elements: [element])
  }

  // MARK: - Materials

  private static func makeOutlineMaterial(color: UIColor) -> SCNMaterial {
    let mat = SCNMaterial()
    mat.diffuse.contents = color.withAlphaComponent(0.75)
    mat.fillMode = .lines
    mat.isDoubleSided = true
    mat.lightingModel = .constant
    mat.writesToDepthBuffer = false
    mat.blendMode = .alpha
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

    // Sample every 4th face — keeps this cheap on dense meshes.
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

  /// Hackathon palette — distinct + readable on top of the camera feed.
  static func color(for classification: ARMeshClassification) -> UIColor {
    switch classification {
    case .wall:    return UIColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1.0)
    case .floor:   return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
    case .ceiling: return UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.0)
    case .table:   return UIColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1.0)
    case .seat:    return UIColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1.0)
    case .door:    return UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0)
    case .window:  return UIColor(red: 0.39, green: 0.82, blue: 1.00, alpha: 1.0)
    case .none:    fallthrough
    @unknown default:
      return UIColor(white: 1.0, alpha: 1.0)
    }
  }
}
