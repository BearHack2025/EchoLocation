import ARKit
import ExpoModulesCore

public final class EchoLidarModule: Module {
  /// Weak reference so the preview view + ARSnapshotCapture can find the live module
  /// to attach its ARSCNView / read currentFrame.
  public static weak var current: EchoLidarModule?

  private let sessionController = EchoLidarSession()
  private let voiceCommandController = VoiceCommandController()
  private let wakeWordListener = WakeWordListener()
  private let queryRecorder = QueryAudioRecorder()
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

    Events("onEchoUpdate", "onVoiceCommand", "onModelStatus", "onThermalState", "onWakeWord")

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

    // MARK: - Wake-word listener (Phase 2)

    /// Continuous on-device "hey echo" / "echo" recognizer. Emits `onWakeWord`
    /// when matched. Caller (the JS orchestrator) typically stops this before
    /// recording the user's query so the mic isn't double-claimed.
    AsyncFunction("startWakeListener") { [weak self] in
      guard let self else { return }
      try await self.wakeWordListener.start { [weak self] phrase in
        self?.sendEvent("onWakeWord", [
          "phrase": phrase,
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ])
      }
    }

    AsyncFunction("stopWakeListener") { [weak self] in
      await MainActor.run {
        self?.wakeWordListener.stop()
      }
    }

    // MARK: - Query audio recording (Phase 3)

    /// Records up to `maxSeconds` (default 6) of microphone audio to a temp
    /// M4A file at 16 kHz mono. Returns the file URL as a string. The JS side
    /// hands the URL to ElevenLabs Scribe for transcription.
    AsyncFunction("recordQueryAudio") { [weak self] (maxSeconds: Double?) -> String in
      guard let self else { return "" }
      let url = try await self.queryRecorder.record(maxSeconds: maxSeconds ?? 6.0)
      return url.absoluteString
    }

    AsyncFunction("stopQueryAudio") { [weak self] in
      await MainActor.run {
        self?.queryRecorder.stop()
      }
    }

    // MARK: - Gemma vision Q&A (Phase 4)

    /// One-sentence answer to a transcribed user question, grounded in the
    /// current AR camera frame + latest LiDAR snapshot. Returns plain string.
    AsyncFunction("quickQuery") { [weak self] (
      question: String,
      distanceM: Double,
      direction: String,
      label: String
    ) -> String in
      guard let self else { return "" }
      let image = try ARSnapshotCapture.captureCurrentFrame()
      return try await self.gemma.quickQuery(
        question: question,
        distanceM: distanceM,
        direction: direction,
        label: label,
        image: image
      )
    }

    /// Wake-only briefing: 1–2 sentence description of the user's surroundings
    /// + recommended next move. Triggered by "hey echo" — no user query text.
    AsyncFunction("wakeBriefing") { [weak self] (
      distanceM: Double,
      direction: String,
      label: String
    ) -> String in
      guard let self else { return "" }
      let image = try ARSnapshotCapture.captureCurrentFrame()
      return try await self.gemma.wakeBriefing(
        image: image,
        distanceM: distanceM,
        direction: direction,
        label: label
      )
    }

    // MARK: - Native speech (DISABLED — ElevenLabs-only)

    /// ElevenLabs-only mode: native AVSpeechSynthesizer is intentionally
    /// disabled so the user can never hear the iPhone's built-in voice as a
    /// fallback. Calls here are no-ops. See plan
    /// 260425-1648-elevenlabs-only-and-auto-start.
    AsyncFunction("speak") { (_: String) in
      NSLog("[EchoLidar] speak() called but ignored — app is ElevenLabs-only")
    }

    AsyncFunction("stopSpeaking") {
      // Nothing to stop — ElevenLabs player on the JS side owns its own playback.
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
