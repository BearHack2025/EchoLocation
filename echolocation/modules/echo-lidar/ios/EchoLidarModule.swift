import ARKit
import ExpoModulesCore

public final class EchoLidarModule: Module {
  /// Weak reference so the preview view + ARSnapshotCapture can find the live module
  /// to attach its ARSCNView / read currentFrame.
  public static weak var current: EchoLidarModule?

  private let sessionController = EchoLidarSession()
  private let voiceCommandController = VoiceCommandController()
  private let gemma = GemmaInferenceController.shared

  /// Exposed so EchoLidarPreviewView + ARSnapshotCapture can attach to sharedARSession.
  var session: EchoLidarSession { sessionController }

  /// Single shared SpeechController — see comment in EchoLidarSession.
  /// Reservation/release/say/stop all hit the SAME AVSpeechSynthesizer queue.
  private var speechController: SpeechController { sessionController.speechController }

  public func definition() -> ModuleDefinition {
    Name("EchoLidar")

    OnCreate { [weak self] in
      EchoLidarModule.current = self
      self?.gemma.onStateChanged = { [weak self] payload in
        self?.sendEvent("onModelStatus", payload)
      }
      self?.installThermalObserver()
    }

    Events("onEchoUpdate", "onVoiceCommand", "onModelStatus", "onThermalState")

    View(EchoLidarPreviewView.self) {
      Prop("showHeatmap") { (view: EchoLidarPreviewView, value: Bool?) in
        view.showHeatmap = value ?? true
      }
    }

    // MARK: - Capability checks

    Function("isSupported") {
      ARWorldTrackingConfiguration.isSupported
    }

    Function("supportsDepth") {
      ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
    }

    Function("supportsMeshClassification") {
      ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    Function("getSupportStatus") {
      return [
        "isARSupported": ARWorldTrackingConfiguration.isSupported,
        "supportsDepth": ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]),
        "supportsMeshClassification": ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
      ]
    }

    // MARK: - Session lifecycle (existing)

    AsyncFunction("start") { [weak self] (mode: String?) in
      guard let self else { return }
      try self.sessionController.start(
        mode: mode ?? "describe",
        sendEvent: { name, payload in
          self.sendEvent(name, payload)
        }
      )
    }

    AsyncFunction("stop") { [weak self] in
      self?.sessionController.stop()
    }

    AsyncFunction("startVoiceCommands") { [weak self] in
      guard let self else { return }
      try await self.voiceCommandController.startListening { payload in
        self.sendEvent("onVoiceCommand", payload)
      }
    }

    AsyncFunction("stopVoiceCommands") { [weak self] in
      await MainActor.run {
        self?.voiceCommandController.stopListening()
      }
    }

    // MARK: - Native speech (orchestrator-driven)

    AsyncFunction("speak") { [weak self] (text: String) in
      await MainActor.run {
        self?.speechController.say(text)
      }
    }

    AsyncFunction("stopSpeaking") { [weak self] in
      await MainActor.run {
        self?.speechController.stop()
      }
    }

    /// Voice-command path opens this gate before speaking. Suppresses the
    /// always-on `process(update:)` phrasing so two voices never overlap.
    AsyncFunction("beginVoiceSpeech") { [weak self] in
      await MainActor.run {
        self?.speechController.reserve()
      }
    }

    /// Closes the gate; always-on phrasing resumes immediately.
    AsyncFunction("endVoiceSpeech") { [weak self] in
      await MainActor.run {
        self?.speechController.release()
      }
    }

    // MARK: - Gemma model provisioning (Phase 1)

    Function("getModelStatus") { [weak self] () -> [String: Any] in
      self?.gemma.snapshotStatus() ?? ["state": "idle"]
    }

    AsyncFunction("downloadModel") { [weak self] in
      try await self?.gemma.ensureDownloaded()
    }

    AsyncFunction("cancelDownload") { [weak self] in
      self?.gemma.cancelDownload()
    }

    Function("setUseMockInference") { [weak self] (mock: Bool) in
      self?.gemma.useMockBackend = mock
    }

    /// Toggle event-driven Gemma labels in the always-on path.
    /// `false` reverts to MeshClassifier-only labeling (Phase-3-of-UI behavior).
    Function("setLabelSource") { [weak self] (useGemma: Bool) in
      self?.session.labelTrigger.useGemma = useGemma
    }

    /// Returns the source of the most recent label: "gemma" | "mesh" | "init".
    Function("getLabelSource") { [weak self] () -> String in
      self?.session.labelTrigger.labelSource ?? "init"
    }

    /// Toggle event-driven summarized speech (vs the always-on template loop).
    /// `true` = danger triggers + Gemma summaries drive describe-mode speech.
    /// `false` = falls back to the existing template phrasing per cooldown.
    Function("setEventDrivenSpeech") { [weak self] (enabled: Bool) in
      self?.session.setEventDrivenSpeech(enabled: enabled)
    }

    Function("getEventDrivenSpeech") { [weak self] () -> Bool in
      self?.session.eventDrivenSpeechEnabled ?? true
    }

    /// Returns the current thermal state as a string.
    Function("getThermalState") { () -> String in
      Self.thermalStateName(ProcessInfo.processInfo.thermalState)
    }

    // MARK: - Gemma inference (Phase 2 + 3)

    AsyncFunction("describeScene") { [weak self] (prompt: String) -> [String: Any] in
      guard let self else {
        return ["sentence": "", "objects": [String](), "latencyMs": 0]
      }
      let t0 = Date()
      let result = try await self.gemma.describeScene(prompt: prompt)
      let ms = Int(Date().timeIntervalSince(t0) * 1000)
      return [
        "sentence": result.sentence,
        "objects": result.objects,
        "latencyMs": ms
      ]
    }

    AsyncFunction("recommendDirection") { [weak self] (
      prompt: String,
      distanceM: Double?,
      lidarDirection: String,
      lidarLabel: String
    ) -> [String: Any] in
      guard let self else {
        return [
          "direction": "stop",
          "confidence": 0.0,
          "reason": "module unavailable",
          "sentence": "I can't tell right now.",
          "source": "lidar-fallback",
          "latencyMs": 0
        ]
      }

      let ctx = LidarFallback.Context(
        distanceM: distanceM,
        lidarDirection: lidarDirection,
        lidarLabel: lidarLabel
      )
      let t0 = Date()
      do {
        let result = try await self.gemma.recommendDirection(
          prompt: prompt,
          fallbackContext: ctx
        )
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        return [
          "direction": result.direction.rawValue,
          "confidence": result.confidence,
          "reason": result.reason,
          "sentence": result.sentence,
          "source": "gemma",
          "latencyMs": ms
        ]
      } catch {
        let fb = LidarFallback.makeDirectionResult(ctx)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        return [
          "direction": fb.direction,
          "confidence": fb.confidence,
          "reason": fb.reason,
          "sentence": fb.sentence,
          "source": fb.source,
          "latencyMs": ms
        ]
      }
    }
  }

  // MARK: - Thermal observer

  private func installThermalObserver() {
    NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      let state = ProcessInfo.processInfo.thermalState
      let name = Self.thermalStateName(state)

      // Pause Gemma at .serious / .critical so we don't drive thermal further up.
      let throttle = (state == .serious || state == .critical)
      self.session.labelTrigger.thermalThrottled = throttle

      self.sendEvent("onThermalState", [
        "state": name,
        "throttled": throttle
      ])
    }
  }

  private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal:  return "nominal"
    case .fair:     return "fair"
    case .serious:  return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }
}
