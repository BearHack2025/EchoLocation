import AVFoundation
import Foundation

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
  private let synthesizer = AVSpeechSynthesizer()
  private var audioPlayer: AVAudioPlayer?
  private var pendingCompletion: ((Bool, String?) -> Void)?

  private var lastPhrase = ""
  private var lastSpokenAt: Date = .distantPast
  private var lastDirection = ""
  private var lastDistanceBucket = -1

  private let repeatInterval: TimeInterval = 3.0
  private let minInterval: TimeInterval = 1.0

  private var useBuiltinSpeech: Bool = true
  private var speechRate: Float = 0.5
  private var speechPitch: Float = 1.0
  private var speechVoice: String = "en-US"

  private var isAwaitingAudio: Bool = false

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  var isSpeaking: Bool {
    return synthesizer.isSpeaking || (audioPlayer?.isPlaying ?? false) || isAwaitingAudio
  }

  func configureBuiltinSpeech(useBuiltin: Bool, rate: Float = 0.5, pitch: Float = 1.0, voice: String = "en-US") {
    useBuiltinSpeech = useBuiltin
    speechRate = rate
    speechPitch = pitch
    speechVoice = voice
  }

  private func requestSpeech(text: String, mode: String, onSpeechRequest: @escaping (String, String) -> Void) {
    if useBuiltinSpeech {
      speakBuiltin(text: text, mode: mode)
    } else {
      lastPhrase = text
      lastSpokenAt = Date()
      isAwaitingAudio = true
      onSpeechRequest(text, mode)
    }
  }

  private func speakBuiltin(text: String, mode: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = speechRate
    utterance.pitchMultiplier = speechPitch
    utterance.voice = AVSpeechSynthesisVoice(language: speechVoice)
    utterance.preUtteranceDelay = 0.05
    utterance.postUtteranceDelay = 0.05

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("[SpeechController] Audio session error: \(error.localizedDescription)")
    }

    lastPhrase = text
    lastSpokenAt = Date()
    synthesizer.speak(utterance)
  }

  func speakBuiltinText(_ text: String, completion: ((Bool, String?) -> Void)? = nil) {
    speakBuiltin(text: text, mode: "direct")
  }

  func process(update: [String: Any], mode: String, onSpeechRequest: @escaping (String, String) -> Void) {
    guard mode != "quiet" else { return }
    guard !isSpeaking else { return }

    guard
      let distance = update["nearestDistanceMeters"] as? Double,
      let direction = update["direction"] as? String,
      let label = update["label"] as? String
    else { return }

    if mode == "echo" {
      let bucket = distanceBucket(distance)
      guard direction != lastDirection || bucket != lastDistanceBucket else { return }
      lastDirection = direction
      lastDistanceBucket = bucket
      let phrase = shortPhrase(direction: direction, distance: distance)
      requestSpeech(text: phrase, mode: mode, onSpeechRequest: onSpeechRequest)
      return
    }

    let phrase = describePhrase(direction: direction, distance: distance, label: label)
    let now = Date()
    let sinceLast = now.timeIntervalSince(lastSpokenAt)

    let directionChanged = direction != lastDirection
    let bucketChanged = distanceBucket(distance) != lastDistanceBucket

    let shouldSpeak = directionChanged
      || (bucketChanged && sinceLast >= minInterval)
      || (phrase != lastPhrase && sinceLast >= repeatInterval)

    guard shouldSpeak else { return }

    lastDirection = direction
    lastDistanceBucket = distanceBucket(distance)
    requestSpeech(text: phrase, mode: mode, onSpeechRequest: onSpeechRequest)
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    audioPlayer?.stop()
    audioPlayer = nil
    lastPhrase = ""
    lastSpokenAt = .distantPast
    lastDirection = ""
    lastDistanceBucket = -1
    pendingCompletion = nil
    isAwaitingAudio = false

    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("[SpeechController] Audio session deactivation error: \(error.localizedDescription)")
    }
  }

  // Called by JS once it has finished (or failed) playing the ElevenLabs clip
  // through expo-audio. Native does not play the URL itself in this flow —
  // the JS player owns playback, and this signal only releases the speech gate.
  func onAudioReady(audioUrl: String, completion: @escaping (Bool, String?) -> Void) {
    isAwaitingAudio = false
    completion(true, nil)
  }

  func onSpeechFailed() {
    isAwaitingAudio = false
  }

  private func shortPhrase(direction: String, distance: Double) -> String {
    let dir = direction == "center" ? "ahead" : direction
    return "\(dir), \(formattedDistance(distance))"
  }

  private func describePhrase(direction: String, distance: Double, label: String) -> String {
    let dir = direction == "center" ? "ahead" : "to your \(direction)"
    let dist = formattedDistance(distance)
    return "\(label) \(dir), \(dist)"
  }

  private func formattedDistance(_ meters: Double) -> String {
    if meters < 1.0 {
      return "very close"
    } else if meters < 2.0 {
      let rounded = (meters * 10).rounded() / 10
      return "\(rounded) meters"
    } else {
      return "\(Int(meters.rounded())) meters"
    }
  }

  private func distanceBucket(_ meters: Double) -> Int {
    switch meters {
    case ..<0.5: return 0
    case ..<1.0: return 1
    case ..<1.5: return 2
    case ..<2.5: return 3
    default: return 4
    }
  }
}

extension SpeechController: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    pendingCompletion?(flag, flag ? nil : "Playback failed")
    pendingCompletion = nil
    audioPlayer = nil
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    pendingCompletion?(false, error?.localizedDescription ?? "Decode error")
    pendingCompletion = nil
    audioPlayer = nil
  }
}
