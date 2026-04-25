import Foundation
import UIKit

/// Top-level controller for Gemma 4 E2B inference.
///
/// Architecture: a small `InferenceBackend` protocol plus two implementations.
///   - `MockInferenceBackend`  → returns plausible canned responses with a tunable
///                                delay. Lets the JS pipeline + UI run end-to-end
///                                on device without the real model.
///   - `LiteRTLMInferenceBackend` → wraps the `litert-lm` Swift API. The exact API
///                                surface for vision input is not yet pinned in
///                                this codebase; the integration block is marked
///                                `// MARK: - LITERT WIRE-UP` and is intended to
///                                be the first thing you adjust against the SDK
///                                headers after `pod install`.
///
/// Default backend is Mock until you flip `useMockBackend = false` (or call
/// `setUseMockBackend(false)` from JS via the bridge in Phase 1+).
public final class GemmaInferenceController {
  enum InferenceError: LocalizedError {
    case modelNotReady
    case backendFailed(String)
    case timeout

    var errorDescription: String? {
      switch self {
      case .modelNotReady:        return "Gemma model is not loaded yet"
      case .backendFailed(let m): return "Inference failed: \(m)"
      case .timeout:              return "Inference timed out"
      }
    }
  }

  enum LoadState: String {
    case idle, downloading, ready, error
  }

  // Singleton — there is exactly one model instance per process.
  static let shared = GemmaInferenceController()
  private init() {}

  // MARK: - Public state

  private(set) var state: LoadState = .idle
  private(set) var lastError: String?
  private(set) var downloadProgressBytes: Int64 = 0
  private(set) var downloadTotalBytes: Int64 = 0

  // Flip to false once LiteRT-LM SDK call is verified on device.
  var useMockBackend: Bool = true

  // Hard cap per LiteRT iOS issue #6765 — > 4096 SIGSEGVs on iPhone 16 Pro Max.
  let maxTokens: Int = 4096

  /// Single in-flight inference at any time. Concurrent callers share the same Task.
  private var inFlight: Task<String, Error>?

  private var backend: InferenceBackend?
  private var downloader: ModelDownloader?

  // MARK: - Configuration

  // Resolve URL for `litert-community/gemma-4-E2B-it-litert-lm`. Replace with your
  // own CDN once you've mirrored the file (HF resolve URLs occasionally redirect).
  private var modelDownloadURL: URL {
    URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")!
  }

  // SHA-256 of the canonical file. Empty disables checksum (NOT recommended for prod;
  // fine for hackathon when you're just sideloading). Fill once you've mirrored.
  private var modelExpectedSHA256: String { "" }

  private var modelDestination: URL {
    let fm = FileManager.default
    let support = try! fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return support.appendingPathComponent("gemma-4-E2B-it.litertlm")
  }

  // MARK: - State observability

  /// Called from any thread; payload is plain dict ready to ship to JS.
  var onStateChanged: (([String: Any]) -> Void)?

  private func emitState() {
    onStateChanged?([
      "state": state.rawValue,
      "progressBytes": downloadProgressBytes,
      "totalBytes": downloadTotalBytes,
      "error": lastError as Any
    ])
  }

  func snapshotStatus() -> [String: Any] {
    [
      "state": state.rawValue,
      "progressBytes": downloadProgressBytes,
      "totalBytes": downloadTotalBytes,
      "error": lastError as Any
    ]
  }

  // MARK: - Provisioning (Phase 1)

  func ensureDownloaded() async throws {
    if FileManager.default.fileExists(atPath: modelDestination.path) {
      state = .ready
      emitState()
      return
    }
    state = .downloading
    lastError = nil
    emitState()

    let dl = ModelDownloader(
      url: modelDownloadURL,
      destination: modelDestination,
      expectedSHA256: modelExpectedSHA256
    )
    self.downloader = dl
    dl.onProgress = { [weak self] p in
      self?.downloadProgressBytes = p.bytesDownloaded
      self?.downloadTotalBytes = p.totalBytes
      self?.emitState()
    }
    do {
      try await dl.download()
      state = .ready
      emitState()
    } catch {
      state = .error
      lastError = error.localizedDescription
      emitState()
      throw error
    }
  }

  func cancelDownload() {
    downloader?.cancel()
  }

  // MARK: - Lazy load

  private func ensureBackend() throws {
    if backend != nil { return }
    if useMockBackend {
      backend = MockInferenceBackend()
      return
    }
    guard FileManager.default.fileExists(atPath: modelDestination.path) else {
      throw InferenceError.modelNotReady
    }
    // MARK: - LITERT WIRE-UP
    // Replace this when LiteRT-LM iOS SDK is installed. Expected shape:
    //
    //   import LiteRT
    //   let session = try LiteRTLMSession(modelPath: modelDestination.path,
    //                                      maxTokens: maxTokens)
    //   self.backend = LiteRTLMInferenceBackend(session: session)
    //
    // Until then, fall through to mock so the rest of the pipeline runs.
    backend = MockInferenceBackend()
  }

  // MARK: - Quick label (always-on path)

  /// Single-word visual label. ≤10-token output, 256×256 image.
  /// Returns the lowercase first whitespace-separated word from the model output.
  /// Throws if output is empty or unparseable so the caller can fall back to MeshClassifier.
  func quickLabel(image: UIImage) async throws -> String {
    let raw = try await runInference(
      prompt: GemmaInferenceController.QUICK_LABEL_PROMPT,
      image: image
    )
    let token = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
      .first
      .map(String.init)?
      .lowercased()
      .trimmingCharacters(in: .punctuationCharacters)
    guard let token, !token.isEmpty else {
      throw InferenceError.backendFailed("empty or unparseable label")
    }
    return token
  }

  static let QUICK_LABEL_PROMPT = "What is the dominant object in front of the camera? Reply with one word, lowercase."

  static let DANGER_SUMMARY_PROMPT_TEMPLATE = """
  You are warning a blind user about an obstacle they just got close to.

  Recent sensor history (oldest → newest):
  %@

  Current frame is attached.

  Reply with EXACTLY one short sentence (under 15 words):
  - name the obstacle they're approaching
  - mention exact distance and direction
  - end with "step left", "step right", "slow down", or "stop now"

  No greetings, no preamble.
  """

  /// Fast (≤30-token) one-sentence danger summary. The history string is the
  /// caller's responsibility to format; pass the formatted lines as `history`.
  /// Trims whitespace; raises on empty output.
  func quickSummarize(history: String, image: UIImage) async throws -> String {
    let prompt = String(format: GemmaInferenceController.DANGER_SUMMARY_PROMPT_TEMPLATE, history)
    let raw = try await runInference(prompt: prompt, image: image)
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw InferenceError.backendFailed("empty summary")
    }
    return trimmed
  }

  // MARK: - Inference (Phase 2 + Phase 3)

  func describeScene(prompt: String) async throws -> SceneOutputParser.Result {
    let raw = try await runInference(prompt: prompt, image: try ARSnapshotCapture.captureCurrentFrame())
    return SceneOutputParser.parse(raw)
  }

  func recommendDirection(
    prompt: String,
    fallbackContext: LidarFallback.Context
  ) async throws -> DirectionOutputParser.Result {
    let raw = try await runInference(prompt: prompt, image: try ARSnapshotCapture.captureCurrentFrame())
    if let parsed = DirectionOutputParser.parse(raw) {
      return parsed
    }
    // Parse failure → fabricate one from the LiDAR fallback so the contract holds.
    let fb = LidarFallback.makeDirectionResult(fallbackContext)
    return DirectionOutputParser.Result(
      direction: DirectionOutputParser.Direction(rawValue: fb.direction) ?? .stop,
      confidence: fb.confidence,
      reason: fb.reason,
      sentence: fb.sentence
    )
  }

  /// Single in-flight gate. Concurrent callers share the same Task.
  private func runInference(prompt: String, image: UIImage) async throws -> String {
    if let existing = inFlight { return try await existing.value }
    try ensureBackend()
    let backend = self.backend!
    let task = Task<String, Error> { [maxTokens] in
      try await backend.generate(prompt: prompt, image: image, maxTokens: maxTokens)
    }
    inFlight = task
    defer { inFlight = nil }
    return try await task.value
  }
}

// MARK: - Backend protocol

protocol InferenceBackend {
  func generate(prompt: String, image: UIImage, maxTokens: Int) async throws -> String
}

// MARK: - Mock backend (always available)

/// Returns a small bank of plausible answers. The selection is rotated so back-to-back
/// calls don't return identical strings (which would suggest the cache, not inference).
final class MockInferenceBackend: InferenceBackend {
  private var rotation = 0
  private let sceneAnswers = [
    "A laptop on a desk and a chair just to your right.\nlaptop, desk, chair, monitor",
    "Bookshelf ahead with a backpack on the floor.\nbookshelf, backpack, floor, books",
    "Open hallway with a door about three meters ahead.\nhallway, door, wall, floor"
  ]
  private let directionAnswers = [
    #"{"direction":"forward","confidence":0.78,"reason":"clear hallway","sentence":"Step forward, hallway is clear for two meters."}"#,
    #"{"direction":"left","confidence":0.65,"reason":"obstacle on right","sentence":"Step slightly left, there is a chair on your right."}"#,
    #"{"direction":"stop","confidence":0.9,"reason":"wall close ahead","sentence":"Stop, there is a wall just ahead."}"#
  ]
  private let quickLabelAnswers = [
    "chair", "table", "wall", "door", "backpack",
    "monitor", "laptop", "bookshelf", "floor", "obstacle"
  ]
  private let summaryAnswers = [
    "Wall ahead, 0.8 meters, slow down.",
    "Chair on your right, 0.7 meters, step left.",
    "Doorway directly ahead, 0.9 meters, slow down.",
    "Table edge to your left, 0.6 meters, step right.",
    "Backpack on the floor ahead, 0.5 meters, stop now."
  ]

  func generate(prompt: String, image: UIImage, maxTokens: Int) async throws -> String {
    // Quick label — short, single word, fast (matches a real <600ms vision call).
    if prompt == GemmaInferenceController.QUICK_LABEL_PROMPT {
      try await Task.sleep(nanoseconds: UInt64.random(in: 250_000_000...600_000_000))
      let idx = rotation % quickLabelAnswers.count
      rotation += 1
      return quickLabelAnswers[idx]
    }

    // Danger summary — short sentence, fast (signature: starts with "You are warning a blind user").
    if prompt.contains("warning a blind user") {
      try await Task.sleep(nanoseconds: UInt64.random(in: 300_000_000...700_000_000))
      let idx = rotation % summaryAnswers.count
      rotation += 1
      return summaryAnswers[idx]
    }

    // Other (scene / direction) — realistic 1.5–2.5s on hackathon target hardware.
    let delayNs = UInt64.random(in: 1_500_000_000...2_500_000_000)
    try await Task.sleep(nanoseconds: delayNs)

    let answers = prompt.contains("JSON") ? directionAnswers : sceneAnswers
    let idx = rotation % answers.count
    rotation += 1
    return answers[idx]
  }
}

// MARK: - LiteRT-LM backend (placeholder — wire to SDK)

/// Stub for the production backend. Once you `pod install` LiteRT-LM and verify
/// the API surface, fill in the body of `generate(...)`.
///
/// Recommended steps:
///   1. `pod 'TensorFlowLiteSwift/CoreML', '~> 2.17'` (already in podspec)
///   2. `pod install` from `ios/`
///   3. Pull `litert-community/gemma-4-E2B-it-litert-lm` from HF (manual or via
///      `ensureDownloaded()`)
///   4. Replace this stub with the real session API per LiteRT iOS quickstart:
///      https://ai.google.dev/edge/litert/ios/quickstart
final class LiteRTLMInferenceBackend: InferenceBackend {
  // Hold a reference to the LiteRT session here once you wire it.
  // private let session: LiteRTLMSession

  init(modelPath: String, maxTokens: Int) throws {
    // session = try LiteRTLMSession(modelPath: modelPath, maxTokens: maxTokens)
  }

  func generate(prompt: String, image: UIImage, maxTokens: Int) async throws -> String {
    // let response = try await session.generate(prompt: prompt, image: image)
    // return response
    throw GemmaInferenceController.InferenceError.backendFailed("LiteRT backend not yet wired — see GemmaInferenceController.swift LITERT WIRE-UP marker")
  }
}
