import ARKit
import Foundation
import MLKitTextRecognition
import MLKitVision
import simd

final class OCRTextDetector {
  private let recognizer: TextRecognizer
  private var inFlight = false
  private var frameCounter = 0

  // Run OCR at a moderate rate to keep it responsive without overwhelming speech.
  private let frameStride = 8

  init() {
    recognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())
  }

  func detectIfReady(
    frame: ARFrame,
    completion: @escaping ([OCRTextDetection]) -> Void
  ) -> Bool {
    frameCounter += 1
    guard !inFlight, frameCounter % frameStride == 0 else {
      return false
    }
    inFlight = true

    let pixelBuffer = frame.capturedImage
    let camera = frame.camera
    let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth

    let visionImage = VisionImage(buffer: makeSampleBuffer(pixelBuffer: pixelBuffer))
    visionImage.orientation = .right

    recognizer.process(visionImage) { [weak self] text, error in
      guard let self else { return }
      defer { self.inFlight = false }

      guard error == nil, let text, !text.blocks.isEmpty else {
        completion([])
        return
      }

      let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
      let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

      var results: [OCRTextDetection] = []
      for block in text.blocks {
        let cleaned = self.normalizedText(block.text)
        let canonical = self.canonicalText(cleaned)
        guard canonical.count >= 2 else { continue }

        let bbox = block.frame
        let centerX = bbox.midX
        let centerY = bbox.midY
        let normX = centerX / imageWidth
        let normY = centerY / imageHeight

        guard let depth = self.sampleDepth(depthData: depthData, normX: Float(normX), normY: Float(normY)),
              depth > 0.05,
              depth < 8.0 else {
          continue
        }

        let worldPoint = self.unproject(
          camera: camera,
          imagePoint: CGPoint(x: centerX, y: centerY),
          imageSize: CGSize(width: imageWidth, height: imageHeight),
          depth: depth
        )

        results.append(
          OCRTextDetection(
            text: cleaned,
            normalizedText: canonical,
            worldPoint: worldPoint,
            distance: depth,
            bearing: self.bearing(forNormalizedX: Float(normX))
          )
        )
      }

      completion(results)
    }

    return true
  }

  private func normalizedText(_ text: String) -> String {
    let collapsed = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return String(collapsed.prefix(120))
  }

  private func canonicalText(_ text: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(.whitespaces)
    let scalars = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
    let collapsed = String(scalars)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return String(collapsed.prefix(120))
  }

  private func bearing(forNormalizedX x: Float) -> String {
    if x < 0.33 { return "left" }
    if x < 0.66 { return "center" }
    return "right"
  }

  private func sampleDepth(depthData: ARDepthData?, normX: Float, normY: Float) -> Float? {
    guard let depthData else { return nil }
    let depthMap = depthData.depthMap
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

    let rowStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
    let ptr = base.assumingMemoryBound(to: Float32.self)

    let px = max(0, min(width - 1, Int(normX * Float(width))))
    let py = max(0, min(height - 1, Int(normY * Float(height))))

    var samples: [Float] = []
    let radius = max(1, width / 80)
    for dy in -radius...radius {
      for dx in -radius...radius {
        let x = px + dx
        let y = py + dy
        guard x >= 0, x < width, y >= 0, y < height else { continue }
        let value = ptr[y * rowStride + x]
        if value.isFinite && value > 0.05 && value < 8.0 {
          samples.append(value)
        }
      }
    }

    guard !samples.isEmpty else { return nil }
    samples.sort()
    return samples[samples.count / 2]
  }

  private func unproject(
    camera: ARCamera,
    imagePoint: CGPoint,
    imageSize: CGSize,
    depth: Float
  ) -> SIMD3<Float> {
    let viewport = CGSize(width: imageSize.width, height: imageSize.height)
    let unprojected = camera.unprojectPoint(
      imagePoint,
      ontoPlane: matrix_identity_float4x4,
      orientation: .portrait,
      viewportSize: viewport
    )
    let cameraTransform = camera.transform
    let forward = SIMD3<Float>(-cameraTransform.columns.2.x,
                               -cameraTransform.columns.2.y,
                               -cameraTransform.columns.2.z)
    let origin = SIMD3<Float>(cameraTransform.columns.3.x,
                              cameraTransform.columns.3.y,
                              cameraTransform.columns.3.z)
    if let unprojected,
       unprojected.x.isFinite,
       unprojected.y.isFinite,
       unprojected.z.isFinite {
      return unprojected
    }
    return origin + forward * depth
  }

  private func makeSampleBuffer(pixelBuffer: CVPixelBuffer) -> CMSampleBuffer {
    var sampleBuffer: CMSampleBuffer?
    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMTime(value: CMTimeValue(CACurrentMediaTime() * 1000), timescale: 1000),
      decodeTimeStamp: .invalid
    )

    CMSampleBufferCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: formatDescription!,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )

    return sampleBuffer!
  }
}
