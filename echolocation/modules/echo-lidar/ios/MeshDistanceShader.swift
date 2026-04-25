import SceneKit
import UIKit

/// Distance-to-camera shader modifier for the mesh fill layer.
///
/// At SceneKit's `.surface` entry point, `_surface.position` is in view space,
/// so the camera origin is `(0,0,0)` and `length(_surface.position)` is the
/// per-fragment distance to the camera. We map that distance through a
/// red → orange → yellow → green ramp so close surfaces look hot, far ones cool.
enum MeshDistanceShader {
  /// Fill alpha. Tuned for hackathon contrast — high enough to read color,
  /// low enough that the camera underneath stays legible.
  static let fillAlpha: Float = 0.40

  static let surfaceFragment = """
  #pragma body
  float d = length(_surface.position);
  vec3 c;
  if (d < 0.5) {
    c = vec3(1.00, 0.27, 0.23);
  } else if (d < 1.0) {
    c = mix(vec3(1.00, 0.27, 0.23), vec3(1.00, 0.62, 0.04), (d - 0.5) / 0.5);
  } else if (d < 2.0) {
    c = mix(vec3(1.00, 0.62, 0.04), vec3(1.00, 0.92, 0.23), d - 1.0);
  } else if (d < 4.0) {
    c = mix(vec3(1.00, 0.92, 0.23), vec3(0.20, 0.78, 0.35), (d - 2.0) / 2.0);
  } else {
    c = vec3(0.20, 0.78, 0.35);
  }
  _surface.diffuse = vec4(c, \(fillAlpha));
  """

  /// Apply the heatmap shader + the supporting material flags (alpha, depth,
  /// double-sided) to a fill material.
  static func applyHeatmap(to material: SCNMaterial) {
    material.shaderModifiers = [.surface: surfaceFragment]
    material.lightingModel = .constant
    material.isDoubleSided = true
    material.writesToDepthBuffer = false
    material.blendMode = .alpha
    material.transparency = 1.0
  }
}
