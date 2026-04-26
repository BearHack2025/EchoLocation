import ARKit
import Foundation
import Vision

final class OCRDetector {
  private let queue = DispatchQueue(label: "echo.ocr", qos: .utility)
  private var inFlight = false
  private var frameCounter = 0

  // Run OCR ~2 fps assuming a 60 fps ARSession.
  private let frameStride = 30

  // Don't repeat the same text within this window.
  private let repeatCooldown: TimeInterval = 8.0
  // Always wait at least this long between any two OCR speeches.
  private let minSpeakInterval: TimeInterval = 4.0

  private let minConfidence: VNConfidence = 0.5
  private let minCharCount = 3

  private var lastSpokenText: String = ""
  private var lastSpokenAt: Date = .distantPast

  func detectIfReady(frame: ARFrame, speak: @escaping (String) -> Void) {
    frameCounter += 1
    guard !inFlight, frameCounter % frameStride == 0 else { return }

    // Cheap rate limit before doing any Vision work.
    let sinceLast = Date().timeIntervalSince(lastSpokenAt)
    guard sinceLast >= minSpeakInterval else { return }

    inFlight = true
    let pixelBuffer = frame.capturedImage

    queue.async { [weak self] in
      guard let self else { return }
      defer { self.inFlight = false }

      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .fast
      request.usesLanguageCorrection = false
      request.minimumTextHeight = 0.03

      let handler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer,
        orientation: .right,
        options: [:]
      )

      do {
        try handler.perform([request])
      } catch {
        return
      }

      guard let observations = request.results, !observations.isEmpty else { return }

      var pieces: [String] = []
      for obs in observations {
        guard let candidate = obs.topCandidates(1).first,
              candidate.confidence >= self.minConfidence else { continue }
        let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= self.minCharCount {
          pieces.append(trimmed)
        }
      }

      guard !pieces.isEmpty else { return }

      let combined = pieces.joined(separator: ". ")
      let normalized = combined.lowercased()

      if normalized == self.lastSpokenText,
         Date().timeIntervalSince(self.lastSpokenAt) < self.repeatCooldown {
        return
      }

      self.lastSpokenText = normalized
      self.lastSpokenAt = Date()

      DispatchQueue.main.async {
        speak(combined)
      }
    }
  }

  func reset() {
    lastSpokenText = ""
    lastSpokenAt = .distantPast
    frameCounter = 0
  }
}
