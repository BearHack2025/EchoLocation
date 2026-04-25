import ARKit
import Foundation

enum EchoLidarSessionError: LocalizedError {
  case unsupportedARKit
  case unsupportedDepth

  var errorDescription: String? {
    switch self {
    case .unsupportedARKit:
      return "ARKit world tracking is not supported on this device."
    case .unsupportedDepth:
      return "LiDAR scene depth is not supported on this device."
    }
  }
}

final class EchoLidarSession: NSObject, ARSessionDelegate {
  private let arSession = ARSession()
  let labelTrigger = GemmaLabelTrigger()
  private lazy var depthAnalyzer = DepthAnalyzer(labelTrigger: labelTrigger)
  /// Single shared instance — `EchoLidarModule` accesses via `session.speechController`.
  /// Having two would mean two AVSpeechSynthesizer queues = overlapping voices.
  let speechController = SpeechController()

  /// Rolling history of recent EchoUpdate observations. Read by the summarizer
  /// dispatch path to give Gemma context for the warning sentence.
  private let observationBuffer = ObservationBuffer()
  /// Decides WHEN to fire a speech event (rising-edge into danger / rapid
  /// approach / continuous-danger refresh) — gated on confidence ≥ 0.87.
  private var dangerDetector = DangerEventDetector()

  /// Master toggle for the event-driven Gemma path. When true (default), the
  /// always-on template loop in SpeechController is suppressed for `describe`
  /// mode and speech is driven by danger triggers + Gemma summaries here.
  /// JS-exposed via `setEventDrivenSpeech(enabled:)`.
  var eventDrivenSpeechEnabled: Bool = true {
    didSet { speechController.eventDrivenActive = eventDrivenSpeechEnabled }
  }

  /// Single in-flight summary at a time so back-to-back triggers don't pile
  /// concurrent Gemma calls (the controller's own mutex would coalesce, but
  /// we never want even ONE queued behind a current speech utterance).
  private var inFlightSummary = false

  /// Read-only access to the underlying ARSession so a render-only view
  /// (e.g. ARSCNView) can attach without taking ownership of run/pause.
  var sharedARSession: ARSession { arSession }

  private var sendEvent: ((String, [String: Any]) -> Void)?
  private var mode = "describe"
  private var mockTimer: Timer?
  private var useMockEvents = false

  func start(mode: String, sendEvent: @escaping (String, [String: Any]) -> Void) throws {
    self.mode = mode
    self.sendEvent = sendEvent
    observationBuffer.reset()
    dangerDetector.reset()

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
    speechController.stop()
    // Flush any stale state so the next `start()` doesn't see old danger flags.
    observationBuffer.reset()
    dangerDetector.reset()
  }

  func disableMockMode() {
    useMockEvents = false
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard let update = depthAnalyzer.analyze(frame: frame, mode: mode) else {
      return
    }

    // Record + observe. Buffer always records (post-mortem history complete);
    // detector gates internally on confidence ≥ minConfidence.
    if
      let distance = update["nearestDistanceMeters"] as? Double,
      let direction = update["direction"] as? String,
      let label = update["label"] as? String,
      let confidence = update["confidence"] as? Double
    {
      let snap = EchoUpdateSnapshot(
        distanceM: distance,
        direction: direction,
        label: label,
        confidence: confidence,
        timestamp: CACurrentMediaTime()
      )
      observationBuffer.append(snap)
      if let trigger = dangerDetector.observe(snap) {
        NSLog("[EchoLidar] DANGER trigger (conf=%.2f): %@", confidence, "\(trigger)")
        if eventDrivenSpeechEnabled {
          dispatchTriggeredSummary(snap: snap, trigger: trigger, frame: frame)
        }
      }
    }

    speechController.process(update: update, mode: mode)
    sendEvent?("onEchoUpdate", update)
  }

  // MARK: - Event-driven summarized speech (Phase 3)

  private func dispatchTriggeredSummary(
    snap: EchoUpdateSnapshot,
    trigger: DangerEventDetector.Trigger,
    frame: ARFrame
  ) {
    if inFlightSummary { return }
    inFlightSummary = true

    // Capture image NOW — `frame` reference may be released as ARSession advances.
    let image = try? ARSnapshotCapture.image(from: frame.capturedImage)
    let now = CACurrentMediaTime()
    let history = formatHistoryLines(observationBuffer.recent(within: 3.0, now: now))

    Task.detached(priority: .userInitiated) { [weak self] in
      defer { self?.inFlightSummary = false }
      let started = CACurrentMediaTime()
      guard let image else {
        await self?.speakFallback(snap: snap)
        NSLog("[EchoLidar] DANGER summary FAILED — no image; spoke fallback")
        return
      }
      do {
        let sentence = try await GemmaInferenceController.shared.quickSummarize(
          history: history, image: image
        )
        let elapsedMs = (CACurrentMediaTime() - started) * 1000
        NSLog("[EchoLidar] DANGER summary OK (%.0fms): %@", elapsedMs, sentence)
        await MainActor.run { self?.speechController.say(sentence) }
      } catch {
        await self?.speakFallback(snap: snap)
        NSLog("[EchoLidar] DANGER summary FAILED — fallback engaged: %@", "\(error)")
      }
    }
  }

  @MainActor
  private func speakFallback(snap: EchoUpdateSnapshot) {
    let sentence = speechController.describeFallback(
      direction: snap.direction,
      distance: snap.distanceM,
      label: snap.label
    )
    speechController.say(sentence)
  }

  /// Compact history string for Gemma's prompt: oldest first, time deltas in
  /// seconds since the first sample, distance with one decimal.
  private func formatHistoryLines(_ snaps: [EchoUpdateSnapshot]) -> String {
    guard let first = snaps.first else { return "(no recent samples)" }
    return snaps.map { snap -> String in
      let dt = snap.timestamp - first.timestamp
      return String(format: "%.1fs %.1fm %@ %@", dt, snap.distanceM, snap.direction, snap.label)
    }.joined(separator: "\n")
  }

  func setEventDrivenSpeech(enabled: Bool) {
    eventDrivenSpeechEnabled = enabled
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
