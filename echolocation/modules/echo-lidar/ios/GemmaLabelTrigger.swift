import ARKit
import Foundation
import UIKit

/// Owns the always-on label cache. Emits Gemma `quickLabel` calls when the LiDAR
/// signal changes meaningfully (direction flip / distance-band cross / staleness),
/// caches the result, and on Gemma failure falls through to ARKit `MeshClassifier`.
///
/// `currentLabel(...)` is called from the ARSession delegate queue every frame.
/// It NEVER blocks — it returns whatever's in the cache and kicks an async Gemma
/// call when warranted. The cache update happens off-thread; reads are guarded
/// by an NSLock.
final class GemmaLabelTrigger: @unchecked Sendable {
  // MARK: - Tunables (mirrors phase-04 hysteresis values)

  /// Distance band edges in meters (matches the heatmap shader bands).
  private let bandEdges: [Double] = [0.5, 1.0, 2.0, 4.0]
  /// 5% hysteresis on band crossings (Phase 4 will exercise this).
  private let bandHysteresisFraction: Double = 0.05
  /// Min seconds between any two trigger fires.
  private let minIntervalSeconds: TimeInterval = 1.5
  /// Refresh label after this much idle time even if nothing changed.
  private let staleSeconds: TimeInterval = 5.0

  // MARK: - Public state

  /// Toggle Gemma path on / off (for the JS-side debug switch). When false,
  /// every `currentLabel` call falls straight through to MeshClassifier.
  var useGemma: Bool = true {
    didSet { /* state observable via JS getModelStatus or future event */ }
  }

  /// Set true at thermal `.serious`+ to silently disable Gemma calls.
  /// When true, fallback path takes over identically to `useGemma=false`.
  var thermalThrottled: Bool = false

  // MARK: - Private state

  private let gemma: GemmaInferenceController
  private let meshClassifier = MeshClassifier()

  private let lock = NSLock()
  private var cachedLabel: String = "obstacle"
  private var cachedSource: String = "init"   // "gemma" | "mesh" | "init"
  private var lastTriggeredAt: TimeInterval = 0
  private var lastSuccessAt: TimeInterval = 0
  private var lastDistance: Double = -1
  private var lastDirection: String = ""
  private var inFlight: Bool = false

  init(gemma: GemmaInferenceController = .shared) {
    self.gemma = gemma
  }

  // MARK: - Hot-path API (called every frame)

  /// Returns the cached label immediately. Kicks an async Gemma `quickLabel`
  /// when the trigger conditions are met. Fallback to MeshClassifier on error.
  func currentLabel(distance: Double, direction: String, frame: ARFrame) -> String {
    let now = CACurrentMediaTime()

    let snapshotLabel: String = lock.withLock { cachedLabel }
    let useGemmaNow = useGemma && !thermalThrottled

    if useGemmaNow, shouldTrigger(distance: distance, direction: direction, now: now) {
      // Capture frame image NOW, before the AR session moves on.
      let image = try? ARSnapshotCapture.image(from: frame.capturedImage)

      lock.withLock {
        if inFlight { return }
        lastTriggeredAt = now
        lastDistance = distance
        lastDirection = direction
        inFlight = true
      }

      if let image {
        Task.detached(priority: .userInitiated) { [weak self] in
          await self?.runGemma(image: image, frame: frame, distance: distance, direction: direction)
        }
      } else {
        // Pixel-buffer conversion failed — engage fallback synchronously.
        let fallback = meshClassifier.classify(frame: frame, direction: direction, distance: Float(distance))
        lock.withLock {
          self.cachedLabel = fallback
          self.cachedSource = "mesh"
          self.inFlight = false
        }
      }
    }

    return snapshotLabel
  }

  /// Last source the cache came from. JS surface for a debug "G" badge.
  var labelSource: String {
    lock.withLock { cachedSource }
  }

  // MARK: - Trigger logic

  private func shouldTrigger(distance: Double, direction: String, now: TimeInterval) -> Bool {
    let snapshot: (lastTriggeredAt: TimeInterval, lastSuccessAt: TimeInterval, lastDistance: Double, lastDirection: String) =
      lock.withLock { (lastTriggeredAt, lastSuccessAt, lastDistance, lastDirection) }

    if now - snapshot.lastTriggeredAt < minIntervalSeconds { return false }
    if direction != snapshot.lastDirection { return true }
    if bandWithHysteresis(prev: snapshot.lastDistance, current: distance) != band(snapshot.lastDistance) { return true }
    if now - snapshot.lastSuccessAt >= staleSeconds { return true }
    return false
  }

  private func band(_ d: Double) -> Int {
    for (i, edge) in bandEdges.enumerated() where d < edge { return i }
    return bandEdges.count
  }

  private func bandWithHysteresis(prev: Double, current: Double) -> Int {
    let prevBand = band(prev)
    let curBand = band(current)
    if prevBand == curBand { return curBand }

    let edgeIdx = min(prevBand, curBand)
    guard edgeIdx < bandEdges.count else { return curBand }
    let edge = bandEdges[edgeIdx]
    let margin = edge * bandHysteresisFraction
    if curBand > prevBand && current >= edge + margin { return curBand }
    if curBand < prevBand && current <= edge - margin { return curBand }
    return prevBand
  }

  // MARK: - Async Gemma path

  private func runGemma(image: UIImage, frame: ARFrame, distance: Double, direction: String) async {
    do {
      let label = try await gemma.quickLabel(image: image)
      let now = CACurrentMediaTime()
      lock.withLock {
        self.cachedLabel = label
        self.cachedSource = "gemma"
        self.lastSuccessAt = now
        self.inFlight = false
      }
    } catch {
      // Fallback: ARKit mesh classification on the frame we already hold.
      let fallback = meshClassifier.classify(frame: frame, direction: direction, distance: Float(distance))
      lock.withLock {
        self.cachedLabel = fallback
        self.cachedSource = "mesh"
        self.inFlight = false
      }
    }
  }
}

// MARK: - NSLock convenience

private extension NSLock {
  func withLock<T>(_ body: () -> T) -> T {
    lock(); defer { unlock() }
    return body()
  }
}
