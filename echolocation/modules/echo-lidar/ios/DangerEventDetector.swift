import Foundation
import QuartzCore

/// Pure-Swift state machine that decides WHEN to speak. Observes a stream of
/// `EchoUpdateSnapshot`s and returns a `Trigger?` indicating whether the
/// caller should fire a speech event.
///
/// Three trigger types:
///   1. `.rising` — distance crossed into the danger band (≤ 1 m)
///   2. `.rapidApproach` — distance dropped > 0.5 m within 0.5 s
///   3. `.continuousDanger` — user has been in danger band for ≥ 6 s since
///      the last trigger
///
/// All triggers respect a 6 s inter-trigger cooldown except `.continuousDanger`
/// which IS the refresh.
struct DangerEventDetector {
  enum Trigger: CustomStringConvertible {
    case rising(distance: Double, direction: String, label: String)
    case rapidApproach(delta: Double, distance: Double, direction: String, label: String)
    case continuousDanger(distance: Double, direction: String, label: String)

    var description: String {
      switch self {
      case .rising(let d, let dir, let l):
        return String(format: "rising(%.2fm %@ %@)", d, dir, l)
      case .rapidApproach(let delta, let d, let dir, let l):
        return String(format: "rapid(Δ%.2fm → %.2fm %@ %@)", delta, d, dir, l)
      case .continuousDanger(let d, let dir, let l):
        return String(format: "continuous(%.2fm %@ %@)", d, dir, l)
      }
    }
  }

  // MARK: - Tunables

  static let dangerThreshold: Double = 1.0
  static let exitHysteresis: Double = 1.15
  static let approachDelta: Double = 0.5
  static let approachWindow: TimeInterval = 0.5
  static let interTriggerCooldown: TimeInterval = 6.0
  static let continuousDangerInterval: TimeInterval = 6.0
  static let minConfidence: Double = 0.87

  // MARK: - State

  private var wasInDanger = false
  private var lastTriggerAt: TimeInterval = 0
  private var lastSamples: [(distance: Double, t: TimeInterval)] = []
  private let approachHistorySize = 12  // ~1.2 s at 10 Hz

  // MARK: - API

  mutating func observe(_ snap: EchoUpdateSnapshot) -> Trigger? {
    // Confidence gate: drop low-confidence updates entirely. Avoids phantom
    // triggers from glass / mirrors / dark surfaces.
    guard snap.confidence >= Self.minConfidence else { return nil }

    let now = snap.timestamp

    // Always update the rolling-window approach buffer.
    lastSamples.append((snap.distanceM, now))
    if lastSamples.count > approachHistorySize {
      lastSamples.removeFirst()
    }

    // Hysteresis: leaving the danger zone requires clearing exitHysteresis,
    // so noise near the 1.0 m boundary doesn't re-fire `.rising`.
    if wasInDanger && snap.distanceM > Self.exitHysteresis {
      wasInDanger = false
    }

    let cooledDown = (now - lastTriggerAt) >= Self.interTriggerCooldown

    // (1) Rising-edge into danger band.
    if !wasInDanger && snap.distanceM <= Self.dangerThreshold {
      wasInDanger = true
      if cooledDown {
        lastTriggerAt = now
        return .rising(
          distance: snap.distanceM,
          direction: snap.direction,
          label: snap.label
        )
      }
    }

    // (2) Rapid approach inside the last `approachWindow`. Requires ≥3 samples
    // spanning the window so a single jittery frame can't fire it.
    if cooledDown {
      let cutoff = now - Self.approachWindow
      let windowed = lastSamples.filter { $0.t >= cutoff }
      if windowed.count >= 3,
         let oldest = windowed.first,
         oldest.distance - snap.distanceM >= Self.approachDelta {
        lastTriggerAt = now
        return .rapidApproach(
          delta: oldest.distance - snap.distanceM,
          distance: snap.distanceM,
          direction: snap.direction,
          label: snap.label
        )
      }
    }

    // (3) Continuous-danger refresh: re-warn every `continuousDangerInterval`
    // while user remains in the danger band.
    if wasInDanger && (now - lastTriggerAt) >= Self.continuousDangerInterval {
      lastTriggerAt = now
      return .continuousDanger(
        distance: snap.distanceM,
        direction: snap.direction,
        label: snap.label
      )
    }

    return nil
  }

  mutating func reset() {
    wasInDanger = false
    lastTriggerAt = 0
    lastSamples.removeAll()
  }
}
