import Foundation

/// Minimal copy of an EchoUpdate's relevant fields. Stripped of any AR frame
/// reference so it's safe to retain in the rolling history buffer.
struct EchoUpdateSnapshot {
  let distanceM: Double
  let direction: String   // "left" | "center" | "right" | "unknown"
  let label: String
  let confidence: Double  // 0..1, gated by `DangerEventDetector.minConfidence`
  let timestamp: TimeInterval  // CACurrentMediaTime() when observed
}

/// Fixed-capacity ring buffer of EchoUpdate snapshots. Records every observation
/// (regardless of confidence) so post-mortem history is complete; the
/// `DangerEventDetector` is responsible for confidence gating before triggering.
final class ObservationBuffer {
  private var ring: [EchoUpdateSnapshot] = []
  private let capacity: Int

  /// 60 slots ≈ 6 seconds at the AR ~10 Hz event-emit rate.
  init(capacity: Int = 60) {
    self.capacity = capacity
  }

  func append(_ snap: EchoUpdateSnapshot) {
    ring.append(snap)
    if ring.count > capacity {
      ring.removeFirst(ring.count - capacity)
    }
  }

  /// All snapshots within the last `seconds` of `now`. Oldest first.
  func recent(within seconds: TimeInterval, now: TimeInterval) -> [EchoUpdateSnapshot] {
    let cutoff = now - seconds
    return ring.filter { $0.timestamp >= cutoff }
  }

  func reset() {
    ring.removeAll(keepingCapacity: true)
  }
}
