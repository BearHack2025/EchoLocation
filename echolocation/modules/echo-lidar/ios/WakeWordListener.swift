import AVFoundation
import Foundation
import Speech

enum WakeWordListenerError: LocalizedError {
  case speechRecognizerUnavailable
  case onDeviceRecognitionUnsupported
  case speechRecognitionDenied
  case microphoneDenied

  var errorDescription: String? {
    switch self {
    case .speechRecognizerUnavailable:
      return "Speech recognition is unavailable on this device."
    case .onDeviceRecognitionUnsupported:
      return "On-device speech recognition is not supported on this device. Wake word requires it for privacy + battery."
    case .speechRecognitionDenied:
      return "Speech recognition permission was denied."
    case .microphoneDenied:
      return "Microphone permission was denied."
    }
  }
}

/// Continuous on-device speech recognizer that fires `onWake` when the user
/// utters one of the configured wake phrases ("hey echo" / "echo").
///
/// Privacy: `requiresOnDeviceRecognition = true`. Audio never leaves the device
/// for the wake-word path. Cloud STT is used only for the post-wake query
/// (Phase 3 — `QueryAudioRecorder` + ElevenLabs Scribe).
final class WakeWordListener: NSObject {
  // MARK: - Tunables

  /// Wake phrases (lowercased). Token-list matched so "echolocation" doesn't fire.
  private let wakePhrases = ["hey echo", "echo"]

  // (Removed `minPhraseConfidence`. Per Apple docs, partial recognition
  // results always have confidence 0 — only `isFinal == true` populates the
  // confidence value. With `shouldReportPartialResults = true` (we want
  // low-latency wake), gating on confidence rejects every partial and the
  // wake never fires. We trust the transcription text instead; the
  // post-match cooldown + recognition-task restart prevent over-firing.)

  /// Suppress consecutive matches for this long (orchestrator owns the
  /// pipeline and resumes the listener after the response finishes).
  private let cooldownAfterMatchSeconds: TimeInterval = 1.5

  // MARK: - State

  private let audioEngine = AVAudioEngine()
  private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var isListening = false
  private var lastMatchAt: Date = .distantPast
  private var onWake: ((String) -> Void)?

  // MARK: - API

  func start(onWake: @escaping (String) -> Void) async throws {
    NSLog("[WakeWordListener] start() called; supportsOnDevice=%@",
          "\(speechRecognizer?.supportsOnDeviceRecognition ?? false)")
    guard let speechRecognizer, speechRecognizer.isAvailable else {
      throw WakeWordListenerError.speechRecognizerUnavailable
    }
    guard speechRecognizer.supportsOnDeviceRecognition else {
      throw WakeWordListenerError.onDeviceRecognitionUnsupported
    }

    try await requestPermissions()
    NSLog("[WakeWordListener] permissions OK")

    self.onWake = onWake
    self.isListening = true
    self.lastMatchAt = .distantPast

    try configureAudioSession()
    try startRecognitionLoop()
    NSLog("[WakeWordListener] recognition task started")
  }

  func stop() {
    NSLog("[WakeWordListener] stop() called")
    isListening = false
    onWake = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil

    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)

    // Hand back the audio session — Phase 3 recorder will reactivate it.
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Best-effort.
    }
  }

  // MARK: - Permissions

  private func requestPermissions() async throws {
    let speechStatus = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
    guard speechStatus == .authorized else {
      throw WakeWordListenerError.speechRecognitionDenied
    }

    let microphoneGranted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard microphoneGranted else {
      throw WakeWordListenerError.microphoneDenied
    }
  }

  private func configureAudioSession() throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(
      .playAndRecord,
      mode: .measurement,
      options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    )
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Recognition loop

  private func startRecognitionLoop() throws {
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    audioEngine.inputNode.removeTap(onBus: 0)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    recognitionRequest = request

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()
    if !audioEngine.isRunning {
      try audioEngine.start()
    }

    recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }

      if let error {
        NSLog("[WakeWordListener] recognition error: %@", error.localizedDescription)
      }

      if let result {
        self.handleResult(result)
      }
      if result?.isFinal == true || error != nil {
        self.restartIfNeeded()
      }
    }
  }

  private func restartIfNeeded() {
    guard isListening else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self, self.isListening else { return }
      do {
        try self.startRecognitionLoop()
      } catch {
        // Caller can re-invoke `start(...)` if listener stays dead.
      }
    }
  }

  // MARK: - Match logic

  private func handleResult(_ result: SFSpeechRecognitionResult) {
    let text = result.bestTranscription.formattedString.lowercased()
    NSLog("[WakeWordListener] heard \"%@\"", text)

    for phrase in wakePhrases {
      if matchesWakePhrase(text, phrase: phrase) {
        let now = Date()
        if now.timeIntervalSince(lastMatchAt) < cooldownAfterMatchSeconds { return }
        lastMatchAt = now
        NSLog("[WakeWordListener] MATCH \"%@\" → onWake fires", phrase)
        onWake?(phrase)
        // Restart the recognition task to flush the buffer — otherwise the
        // same words keep matching as the partial result grows.
        restartIfNeeded()
        return
      }
    }
  }

  /// True if `phrase` appears as standalone token(s) inside `text`.
  /// Tokenizes on non-alphanumeric characters so punctuation doesn't break
  /// the match. Whole-token equality means "echo" never matches "echolocation".
  private func matchesWakePhrase(_ text: String, phrase: String) -> Bool {
    let words = text
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
    let phraseTokens = phrase
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }

    guard !phraseTokens.isEmpty, words.count >= phraseTokens.count else { return false }
    for start in 0...(words.count - phraseTokens.count) {
      if Array(words[start..<start + phraseTokens.count]) == phraseTokens {
        return true
      }
    }
    return false
  }
}
