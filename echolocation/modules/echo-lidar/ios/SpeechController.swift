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

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  private func requestSpeech(text: String, mode: String, onSpeechRequest: @escaping (String, String) -> Void) {
    onSpeechRequest(text, mode)
  }

  func process(update: [String: Any], mode: String, onSpeechRequest: @escaping (String, String) -> Void) {
    guard mode != "quiet" else { return }

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
  }

  func onAudioReady(audioUrl: String, completion: @escaping (Bool, String?) -> Void) {
    pendingCompletion = completion

    guard let url = URL(string: audioUrl) else {
      completion(false, "Invalid audio URL")
      return
    }

    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      audioPlayer = player
      player.play()
      lastSpokenAt = Date()
    } catch {
      completion(false, error.localizedDescription)
    }
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

