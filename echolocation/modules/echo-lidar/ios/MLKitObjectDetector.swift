import ARKit
import Foundation
import MLKitObjectDetection
import MLKitVision
import simd

final class MLKitObjectDetector {
  private let detector: ObjectDetector
  private var inFlight = false
  private var frameCounter = 0

  // Run detector ~5 fps assuming a 60 fps ARSession.
  private let frameStride = 12

  init() {
    let options = ObjectDetectorOptions()
    options.detectorMode = .stream
    options.shouldEnableClassification = true
    options.shouldEnableMultipleObjects = true
    self.detector = ObjectDetector.objectDetector(options: options)
  }

  /// Returns true if a detection cycle was kicked off for this frame.
  func detectIfReady(
    frame: ARFrame,
    completion: @escaping ([MLKitDetection]) -> Void
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

    detector.process(visionImage) { [weak self] objects, error in
      guard let self else { return }
      defer { self.inFlight = false }

      guard error == nil, let objects, !objects.isEmpty else {
        completion([])
        return
      }

      let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
      let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

      var results: [MLKitDetection] = []
      for object in objects {
        guard let trackingID = object.trackingID?.intValue else { continue }

        let bbox = object.frame
        let centerX = bbox.midX
        let centerY = bbox.midY
        let normX = centerX / imageWidth
        let normY = centerY / imageHeight

        guard let depth = self.sampleDepth(depthData: depthData, normX: Float(normX), normY: Float(normY)),
              depth > 0.05, depth < 8.0 else {
          continue
        }

        let worldPoint = self.unproject(
          camera: camera,
          imagePoint: CGPoint(x: centerX, y: centerY),
          imageSize: CGSize(width: imageWidth, height: imageHeight),
          depth: depth
        )

        let bearing = self.bearing(forNormalizedX: Float(normX))

        let topLabel = object.labels.max(by: { $0.confidence < $1.confidence })
        let labelText = topLabel?.text.lowercased() ?? "object"
        let confidence = Float(topLabel?.confidence ?? 0)

        results.append(MLKitDetection(
          trackingID: trackingID,
          label: labelText,
          confidence: confidence,
          worldPoint: worldPoint,
          distance: depth,
          bearing: bearing
        ))
      }

      completion(results)
    }

    return true
  }

  // MARK: Helpers

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

    // Average a small neighborhood for stability.
    var samples: [Float] = []
    let radius = max(1, width / 80)
    for dy in -radius...radius {
      for dx in -radius...radius {
        let x = px + dx
        let y = py + dy
        guard x >= 0, x < width, y >= 0, y < height else { continue }
        let v = ptr[y * rowStride + x]
        if v.isFinite && v > 0.05 && v < 8.0 {
          samples.append(v)
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
    // Fallback: build world point from camera transform + depth ray.
    let cameraTransform = camera.transform
    let forward = SIMD3<Float>(-cameraTransform.columns.2.x,
                               -cameraTransform.columns.2.y,
                               -cameraTransform.columns.2.z)
    let origin = SIMD3<Float>(cameraTransform.columns.3.x,
                              cameraTransform.columns.3.y,
                              cameraTransform.columns.3.z)
    if let point = unprojected, point.x.isFinite, point.y.isFinite, point.z.isFinite {
      return point
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
