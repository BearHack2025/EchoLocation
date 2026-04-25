import MLKitImageLabeling
import MLKitVision
import UIKit

final class SceneLabeler {
  private let labeler: ImageLabeler

  init() {
    let options = ImageLabelerOptions()
    options.confidenceThreshold = NSNumber(value: 0.65)
    labeler = ImageLabeler.imageLabeler(options: options)
  }

  func label(image: UIImage, limit: Int = 3) throws -> [[String: Any]] {
    let visionImage = VisionImage(image: image)
    visionImage.orientation = image.imageOrientation

    return try labeler
      .results(in: visionImage)
      .sorted { $0.confidence > $1.confidence }
      .prefix(limit)
      .map { label in
        [
          "text": label.text,
          "confidence": label.confidence,
          "index": label.index
        ]
      }
  }
}
