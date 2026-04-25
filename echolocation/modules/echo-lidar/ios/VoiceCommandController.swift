import AVFoundation
import Foundation
import Speech

enum VoiceCommandControllerError: LocalizedError {
  case speechRecognizerUnavailable
  case speechRecognitionDenied
  case microphoneDenied

  var errorDescription: String? {
    switch self {
    case .speechRecognizerUnavailable:
      return "Speech recognition is unavailable on this device."
    case .speechRecognitionDenied:
      return "Speech recognition permission was denied."
    case .microphoneDenied:
      return "Microphone permission was denied."
    }
  }
}

final class VoiceCommandController: NSObject {
  private let audioEngine = AVAudioEngine()
  private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var onCommand: (([String: Any]) -> Void)?
  private var isListening = false
  private var lastEmittedCommand = ""
  private var lastEmittedAt = Date.distantPast
  private let commandCooldown: TimeInterval = 1.5

  func startListening(onCommand: @escaping ([String: Any]) -> Void) async throws {
    guard let speechRecognizer, speechRecognizer.isAvailable else {
      throw VoiceCommandControllerError.speechRecognizerUnavailable
    }

    try await requestPermissions()

    self.onCommand = onCommand
    isListening = true
    lastEmittedCommand = ""
    lastEmittedAt = .distantPast

    try configureAudioSession()
    try startRecognitionLoop()
  }

  func stopListening() {
    isListening = false
    onCommand = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil

    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)

    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Best-effort shutdown; the next session setup will retry if needed.
    }
  }

  private func requestPermissions() async throws {
    let speechStatus = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }

    guard speechStatus == .authorized else {
      throw VoiceCommandControllerError.speechRecognitionDenied
    }

    let microphoneGranted = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }

    guard microphoneGranted else {
      throw VoiceCommandControllerError.microphoneDenied
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

  private func startRecognitionLoop() throws {
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    audioEngine.inputNode.removeTap(onBus: 0)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = false
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
      guard let self else {
        return
      }

      if let transcript = result?.bestTranscription.formattedString {
        self.handleTranscript(transcript)
      }

      if result?.isFinal == true || error != nil {
        self.restartIfNeeded()
      }
    }
  }

  private func restartIfNeeded() {
    guard isListening else {
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self, self.isListening else {
        return
      }

      do {
        try self.startRecognitionLoop()
      } catch {
        // If restart fails, leave listening enabled so callers can retry explicitly.
      }
    }
  }

  private func handleTranscript(_ transcript: String) {
    guard let command = matchedCommand(from: transcript) else {
      return
    }

    let normalizedTranscript = transcript
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    let now = Date()
    let secondsSinceLast = now.timeIntervalSince(lastEmittedAt)

    guard command != lastEmittedCommand || secondsSinceLast >= commandCooldown else {
      return
    }

    lastEmittedCommand = command
    lastEmittedAt = now

    onCommand?([
      "command": command,
      "transcript": normalizedTranscript,
      "timestampMs": Int(now.timeIntervalSince1970 * 1000),
      "source": "speech"
    ])
  }

  private func matchedCommand(from transcript: String) -> String? {
    let text = transcript.lowercased()

    if text.contains("repeat") {
      return "repeat"
    }
    if text.contains("left") {
      return "left"
    }
    if text.contains("right") {
      return "right"
    }
    if text.contains("ahead") || text.contains("what's ahead") || text.contains("what is ahead") || text.contains("in front") {
      return "ahead"
    }

    return nil
  }
}
