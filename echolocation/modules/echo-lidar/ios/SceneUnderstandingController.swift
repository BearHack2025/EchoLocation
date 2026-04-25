import ARKit
import Foundation

private struct SceneSignature {
  let direction: String
  let meshLabel: String
  let distance: Double
  let timestamp: Date
}

private struct VisionSceneResult {
  let signature: SceneSignature
  let labels: [[String: Any]]
  let primaryLabel: String?
  let primaryConfidence: Double
}

final class SceneUnderstandingController {
  private let snapshotController = SnapshotController()
  private let sceneLabeler = SceneLabeler()
  private let analysisQueue = DispatchQueue(label: "expo.modules.echolocation.mlkit", qos: .userInitiated)
  private let stateQueue = DispatchQueue(label: "expo.modules.echolocation.mlkit.state")

  private let minAnalysisInterval: TimeInterval = 2.0
  private let maxReuseAge: TimeInterval = 5.0
  private let minDistanceDelta: Double = 0.45
  private let reuseDistanceTolerance: Double = 0.75
  private let confidentOverrideThreshold: Double = 0.92
  private let genericMeshLabels: Set<String> = ["obstacle", "unknown"]

  private var latestResult: VisionSceneResult?
  private var lastRequestedSignature: SceneSignature?
  private var isProcessing = false

  func enrich(update: [String: Any], frame: ARFrame) -> [String: Any] {
    guard let signature = makeSignature(from: update) else {
      return update
    }

    if shouldAnalyze(signature: signature) {
      scheduleAnalysis(for: signature, frame: frame)
    }

    return applyLatestResult(to: update, signature: signature)
  }

  func reset() {
    stateQueue.sync {
      latestResult = nil
      lastRequestedSignature = nil
      isProcessing = false
    }
  }

  // MARK: - Private

  private func makeSignature(from update: [String: Any]) -> SceneSignature? {
    guard
      let direction = update["direction"] as? String,
      let meshLabel = update["label"] as? String,
      let distance = update["nearestDistanceMeters"] as? Double
    else {
      return nil
    }

    return SceneSignature(
      direction: direction,
      meshLabel: meshLabel,
      distance: distance,
      timestamp: Date()
    )
  }

  private func shouldAnalyze(signature: SceneSignature) -> Bool {
    stateQueue.sync {
      if isProcessing {
        return false
      }

      if let lastRequestedSignature, !sceneChangedMeaningfully(from: lastRequestedSignature, to: signature) {
        let cooldownElapsed = signature.timestamp.timeIntervalSince(lastRequestedSignature.timestamp) >= minAnalysisInterval
        if !cooldownElapsed {
          return false
        }
      }

      guard let latestResult else {
        return true
      }

      let age = signature.timestamp.timeIntervalSince(latestResult.signature.timestamp)
      if age >= maxReuseAge {
        return true
      }

      return sceneChangedMeaningfully(from: latestResult.signature, to: signature)
    }
  }

  private func sceneChangedMeaningfully(from old: SceneSignature, to new: SceneSignature) -> Bool {
    if old.direction != new.direction {
      return true
    }

    if old.meshLabel != new.meshLabel {
      return true
    }

    if abs(old.distance - new.distance) >= minDistanceDelta {
      return true
    }
    
    return false
  }

  private func scheduleAnalysis(for signature: SceneSignature, frame: ARFrame) {
    stateQueue.sync {
      isProcessing = true
      lastRequestedSignature = signature
    }

    analysisQueue.async { [weak self] in
      guard let self else {
        return
      }

      let result: VisionSceneResult?
      do {
        let snapshot = try self.snapshotController.capture(from: frame)
        let labels = try self.sceneLabeler.label(image: snapshot.image)
        let best = labels.first
        result = VisionSceneResult(
          signature: signature,
          labels: labels,
          primaryLabel: best?["text"] as? String,
          primaryConfidence: best?["confidence"] as? Double ?? 0
        )
      } catch {
        result = nil
      }

      self.stateQueue.async {
        self.isProcessing = false
        if let result {
          self.latestResult = result
        }
      }
    }
  }

  private func applyLatestResult(to update: [String: Any], signature: SceneSignature) -> [String: Any] {
    stateQueue.sync {
      guard let latestResult, canReuse(result: latestResult, for: signature) else {
        return update
      }

      var enriched = update
      enriched["meshLabel"] = signature.meshLabel
      enriched["visionLabels"] = latestResult.labels

      if let primaryLabel = latestResult.primaryLabel {
        enriched["visionLabel"] = primaryLabel
        enriched["visionConfidence"] = latestResult.primaryConfidence
      }

      if let preferredLabel = preferredLabel(
        meshLabel: signature.meshLabel,
        visionLabel: latestResult.primaryLabel,
        confidence: latestResult.primaryConfidence
      ) {
        enriched["label"] = preferredLabel
      }

      return enriched
    }
  }

  private func canReuse(result: VisionSceneResult, for signature: SceneSignature) -> Bool {
    let age = signature.timestamp.timeIntervalSince(result.signature.timestamp)
    guard age <= maxReuseAge else {
      return false
    }

    guard result.signature.direction == signature.direction else {
      return false
    }

    guard abs(result.signature.distance - signature.distance) <= reuseDistanceTolerance else {
      return false
    }

    if result.signature.meshLabel == signature.meshLabel {
      return true
    }

    return genericMeshLabels.contains(result.signature.meshLabel) || genericMeshLabels.contains(signature.meshLabel)
  }

  private func preferredLabel(meshLabel: String, visionLabel: String?, confidence: Double) -> String? {
    guard let visionLabel else {
      return meshLabel
    }

    if genericMeshLabels.contains(meshLabel) {
      return visionLabel
    }

    return confidence >= confidentOverrideThreshold ? visionLabel : meshLabel
  }
}
