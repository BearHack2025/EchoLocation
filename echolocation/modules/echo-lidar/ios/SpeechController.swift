import AVFoundation
import Foundation

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
  private let synthesizer = AVSpeechSynthesizer()

  private var lastPhrase = ""
  private var lastSpokenAt: Date = .distantPast
  private var lastDirection = ""
  private var lastDistanceBucket = -1

  // Minimum seconds between identical phrases
  private let repeatInterval: TimeInterval = 3.0
  // Minimum seconds between any speech
  private let minInterval: TimeInterval = 1.0

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func process(update: [String: Any], mode: String) {
    guard mode != "quiet" else { return }

    guard
      let distance = update["nearestDistanceMeters"] as? Double,
      let direction = update["direction"] as? String,
      let label = update["label"] as? String
    else { return }

    if mode == "echo" {
      // Echo mode: short directional cues only on significant change
      let bucket = distanceBucket(distance)
      guard direction != lastDirection || bucket != lastDistanceBucket else { return }
      lastDirection = direction
      lastDistanceBucket = bucket
      speak(shortPhrase(direction: direction, distance: distance))
      return
    }

    // Describe mode: full phrases, throttled
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
    speak(phrase)
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    lastPhrase = ""
    lastSpokenAt = .distantPast
    lastDirection = ""
    lastDistanceBucket = -1
  }

  // MARK: - Private

  private func speak(_ phrase: String) {
    synthesizer.stopSpeaking(at: .word)
    let utterance = AVSpeechUtterance(string: phrase)
    utterance.rate = 0.52
    utterance.pitchMultiplier = 1.0
    utterance.volume = 1.0
    synthesizer.speak(utterance)
    lastPhrase = phrase
    lastSpokenAt = Date()
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

  // Groups distance into coarse buckets to avoid speaking on every tiny change
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
