import ARKit
import CoreImage
import ImageIO
import UIKit

enum SnapshotControllerError: LocalizedError {
  case imageConversionFailed
  case jpegEncodingFailed

  var errorDescription: String? {
    switch self {
    case .imageConversionFailed:
      return "The current AR frame could not be converted into a snapshot."
    case .jpegEncodingFailed:
      return "The captured snapshot could not be encoded as JPEG."
    }
  }
}

struct SnapshotResult {
  let image: UIImage
  let payload: [String: Any]
}

final class SnapshotController {
  private let ciContext = CIContext()
  private let maxDimension: CGFloat = 1280
  private let compressionQuality: CGFloat = 0.72

  func capture(from frame: ARFrame) throws -> SnapshotResult {
    let image = try makeSnapshotImage(from: frame.capturedImage)
    let scaledImage = scaleIfNeeded(image)

    guard let jpegData = scaledImage.jpegData(compressionQuality: compressionQuality) else {
      throw SnapshotControllerError.jpegEncodingFailed
    }

    return SnapshotResult(
      image: scaledImage,
      payload: [
        "jpegBase64": jpegData.base64EncodedString(),
        "width": Int(scaledImage.size.width.rounded()),
        "height": Int(scaledImage.size.height.rounded()),
        "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
        "source": "arkit"
      ]
    )
  }

  private func makeSnapshotImage(from pixelBuffer: CVPixelBuffer) throws -> UIImage {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)

    guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
      throw SnapshotControllerError.imageConversionFailed
    }

    return UIImage(cgImage: cgImage)
  }

  private func scaleIfNeeded(_ image: UIImage) -> UIImage {
    let largestEdge = max(image.size.width, image.size.height)
    guard largestEdge > maxDimension else {
      return image
    }

    let scale = maxDimension / largestEdge
    let targetSize = CGSize(
      width: image.size.width * scale,
      height: image.size.height * scale
    )

    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    format.scale = 1

    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }
}
