import ARKit
import CoreImage
import UIKit

/// Pulls the current AR camera frame as a UIImage.
/// The AR session is owned by `EchoLidarSession`; we read `currentFrame` only —
/// never `run` / `pause`.
enum ARSnapshotCapture {
  enum CaptureError: LocalizedError {
    case sessionNotRunning
    case noFrame
    case conversionFailed

    var errorDescription: String? {
      switch self {
      case .sessionNotRunning: return "AR session is not running"
      case .noFrame:           return "No AR frame available yet"
      case .conversionFailed:  return "Failed to convert pixel buffer to UIImage"
      }
    }
  }

  private static let context = CIContext(options: nil)

  static func captureCurrentFrame() throws -> UIImage {
    guard let module = EchoLidarModule.current else {
      throw CaptureError.sessionNotRunning
    }
    guard let frame = module.session.sharedARSession.currentFrame else {
      throw CaptureError.noFrame
    }
    return try image(from: frame.capturedImage)
  }

  /// Convert a pixel buffer (typically `ARFrame.capturedImage`) to a portrait UIImage.
  /// Used by `GemmaLabelTrigger` so it can snapshot a specific frame at trigger time
  /// without racing against the moving currentFrame pointer.
  static func image(from pixelBuffer: CVPixelBuffer) throws -> UIImage {
    let ci = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
    guard let cg = context.createCGImage(ci, from: ci.extent) else {
      throw CaptureError.conversionFailed
    }
    return UIImage(cgImage: cg)
  }
}
