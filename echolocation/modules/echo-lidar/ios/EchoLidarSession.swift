import ARKit
import Foundation

enum EchoLidarSessionError: LocalizedError {
  case unsupportedARKit
  case unsupportedDepth
  case noCurrentFrame

  var errorDescription: String? {
    switch self {
    case .unsupportedARKit:
      return "ARKit world tracking is not supported on this device."
    case .unsupportedDepth:
      return "LiDAR scene depth is not supported on this device."
    case .noCurrentFrame:
      return "No AR frame is available yet. Start scanning and try again."
    }
  }
}

final class EchoLidarSession: NSObject, ARSessionDelegate {
  private let arSession = ARSession()
  private let depthAnalyzer = DepthAnalyzer()
  private let speechController = SpeechController()
  private let snapshotController = SnapshotController()
  private let sceneLabeler = SceneLabeler()
  private let sceneUnderstandingController = SceneUnderstandingController()

  private var sendEvent: ((String, [String: Any]) -> Void)?
  private var mode = "describe"
  private var mockTimer: Timer?
  private var useMockEvents = false

  func start(mode: String, sendEvent: @escaping (String, [String: Any]) -> Void) throws {
    self.mode = mode
    self.sendEvent = sendEvent

    guard ARWorldTrackingConfiguration.isSupported else {
      throw EchoLidarSessionError.unsupportedARKit
    }

    guard ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) else {
      throw EchoLidarSessionError.unsupportedDepth
    }

    if useMockEvents {
      startMockEvents()
      return
    }

    let configuration = ARWorldTrackingConfiguration()
    configuration.frameSemantics = [.smoothedSceneDepth]

    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
      configuration.sceneReconstruction = .meshWithClassification
    }

    arSession.delegate = self
    arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }

  func stop() {
    mockTimer?.invalidate()
    mockTimer = nil
    arSession.pause()
    depthAnalyzer.reset()
    sceneUnderstandingController.reset()
    speechController.stop()
  }

  func captureSnapshot() throws -> [String: Any] {
    let snapshot = try captureSnapshotResult()
    return snapshot.payload
  }

  func captureAndLabelScene() throws -> [String: Any] {
    let snapshot = try captureSnapshotResult()
    let labels = try sceneLabeler.label(image: snapshot.image)
    return [
      "snapshot": snapshot.payload,
      "labels": labels
    ]
  }

  func disableMockMode() {
    useMockEvents = false
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard let update = depthAnalyzer.analyze(frame: frame, mode: mode) else {
      return
    }

    let enrichedUpdate = sceneUnderstandingController.enrich(update: update, frame: frame)
    speechController.process(update: enrichedUpdate, mode: mode)
    sendEvent?("onEchoUpdate", enrichedUpdate)
  }

  private func startMockEvents() {
    mockTimer?.invalidate()

    let sampleEvents: [[String: Any]] = [
      makePayload(distance: 1.6, direction: "center", label: "obstacle", confidence: 0.72, source: "mock"),
      makePayload(distance: 1.1, direction: "right", label: "table", confidence: 0.81, source: "mock"),
      makePayload(distance: 0.7, direction: "left", label: "wall", confidence: 0.9, source: "mock")
    ]

    var index = 0
    sendEvent?("onEchoUpdate", sampleEvents[index])

    mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self else {
        return
      }

      index = (index + 1) % sampleEvents.count
      self.sendEvent?("onEchoUpdate", sampleEvents[index])
    }
  }

  private func captureSnapshotResult() throws -> SnapshotResult {
    guard let frame = arSession.currentFrame else {
      throw EchoLidarSessionError.noCurrentFrame
    }

    return try snapshotController.capture(from: frame)
  }

  private func makePayload(
    distance: Double?,
    direction: String,
    label: String,
    confidence: Double,
    source: String
  ) -> [String: Any] {
    return [
      "nearestDistanceMeters": distance as Any,
      "direction": direction,
      "label": label,
      "confidence": confidence,
      "mode": mode,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
      "source": source
    ]
  }
}
