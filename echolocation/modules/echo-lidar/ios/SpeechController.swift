import AVFoundation
import Foundation

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
  private let synthesizer = AVSpeechSynthesizer()

  private var lastPhrase = ""
  private var lastSpokenAt: Date = .distantPast
  private var lastDirection = ""
  private var lastDistanceBucket = -1

  /// Hard floor between any two always-on utterances (process path).
  /// Voice-command path (`say()`) bypasses — those are user-requested.
  /// Tunable: 4 s feels appropriate for blind users (avoids overwhelm).
  private let alwaysOnCooldownSeconds: TimeInterval = 4.0

  /// When true, the always-on `process(update:mode:)` path becomes a no-op so
  /// the orchestrator's voice-command speech can play without overlap.
  /// Released on `release()` or auto-released after `reservationSafetyWindow`.
  private(set) var isReserved: Bool = false
  private var reservationExpiresAt: Date = .distantPast
  private let reservationSafetyWindow: TimeInterval = 10

  /// When true, the always-on template loop is suppressed for `describe` mode —
  /// speech is driven by the event-driven Gemma path in EchoLidarSession instead.
  /// Echo mode is unaffected.
  var eventDrivenActive: Bool = true

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  /// Voice-command path opens this gate before speaking. Stops any in-flight
  /// always-on utterance so two voices don't overlap.
  func reserve() {
    isReserved = true
    reservationExpiresAt = Date().addingTimeInterval(reservationSafetyWindow)
    synthesizer.stopSpeaking(at: .immediate)
  }

  /// Voice-command path closes the gate. Always-on phrasing resumes immediately.
  func release() {
    isReserved = false
  }

  func process(update: [String: Any], mode: String) {
    // Auto-release if a `reserve()` was never paired with a `release()`.
    if isReserved && Date() > reservationExpiresAt {
      isReserved = false
    }
    guard !isReserved else { return }
    guard mode != "quiet" else { return }

    // When event-driven speech is active, the describe-mode template loop is
    // suppressed — EchoLidarSession's danger detector + Gemma summarizer
    // drives speech instead. Echo mode (short cues per change) still flows.
    guard !eventDrivenActive || mode == "echo" else { return }

    // Hard cooldown: never speak more than once per `alwaysOnCooldownSeconds`
    // on the always-on path. Blind users find rapid-fire utterances overwhelming.
    let now = Date()
    guard now.timeIntervalSince(lastSpokenAt) >= alwaysOnCooldownSeconds else {
      return
    }

    guard
      let distance = update["nearestDistanceMeters"] as? Double,
      let direction = update["direction"] as? String,
      let label = update["label"] as? String
    else { return }

    if mode == "echo" {
      // Echo mode: short directional cue only on significant change.
      let bucket = distanceBucket(distance)
      guard direction != lastDirection || bucket != lastDistanceBucket else { return }
      lastDirection = direction
      lastDistanceBucket = bucket
      speak(shortPhrase(direction: direction, distance: distance))
      return
    }

    // Describe mode: speak whenever the scene meaningfully changed.
    // Cooldown above bounds the rate; this gate just suppresses no-op utterances.
    let phrase = describePhrase(direction: direction, distance: distance, label: label)
    let directionChanged = direction != lastDirection
    let bucketChanged = distanceBucket(distance) != lastDistanceBucket
    let phraseChanged = phrase != lastPhrase

    guard directionChanged || bucketChanged || phraseChanged else { return }

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

  /// Public entry-point so the JS orchestrator can speak Gemma sentences directly.
  /// Bypasses throttling / repeat suppression — orchestrator owns deduping.
  func say(_ text: String) {
    speak(text)
  }

  /// Pure-function fallback phrasing identical to what the always-on template
  /// path would produce. Used by EchoLidarSession when Gemma fails / is not
  /// ready, so the user always gets *some* audible warning at trigger time.
  func describeFallback(direction: String, distance: Double, label: String) -> String {
    return describePhrase(direction: direction, distance: distance, label: label)
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
    let core = "\(dir), \(speakMeters(distance))"
    if let advice = avoidanceAdvice(direction: direction, distance: distance) {
      return "\(core), \(advice)"
    }
    return core
  }

  private func describePhrase(direction: String, distance: Double, label: String) -> String {
    let dir = direction == "center" ? "ahead" : "to your \(direction)"
    let core = "\(label) \(dir), \(speakMeters(distance))"
    if let advice = avoidanceAdvice(direction: direction, distance: distance) {
      return "\(core), \(advice)"
    }
    return core
  }

  /// Always speak a numeric distance — never the legacy `"very close"`.
  /// Floor at 0.1 m so we never read "0.0 meters" awkwardly.
  /// Decimals under 10 m, integer at or above 10 m.
  private func speakMeters(_ meters: Double) -> String {
    let clamped = max(0.1, meters)
    if clamped < 10 {
      let rounded = (clamped * 10).rounded() / 10
      return "\(rounded) meters"
    }
    return "\(Int(clamped.rounded())) meters"
  }

  /// Action verb the user can act on — only fires when there's a nearby threat
  /// (within 2 m). Beyond that, the user has time; advice would be noise.
  /// `unknown` direction → no advice (we can't honestly tell them where to go).
  private func avoidanceAdvice(direction: String, distance: Double) -> String? {
    guard distance < 2.0 else { return nil }
    if distance < 0.5 { return "stop now" }
    switch direction {
    case "left":   return "step right"
    case "right":  return "step left"
    case "center": return distance < 1.0 ? "stop now" : "slow down"
    default:       return nil
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
