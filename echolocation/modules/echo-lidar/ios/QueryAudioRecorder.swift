import AVFoundation
import Foundation

enum QueryAudioRecorderError: LocalizedError {
  case microphoneDenied
  case sessionConfigFailed(String)
  case recorderInitFailed(String)
  case recordFailed(String)

  var errorDescription: String? {
    switch self {
    case .microphoneDenied:
      return "Microphone permission was denied."
    case .sessionConfigFailed(let m):
      return "Audio session configuration failed: \(m)"
    case .recorderInitFailed(let m):
      return "AVAudioRecorder init failed: \(m)"
    case .recordFailed(let m):
      return "Recording failed: \(m)"
    }
  }
}

/// Records the user's spoken query (post-wake-word) to an M4A file in the temp
/// directory. Output format is tuned for ElevenLabs Scribe: 16 kHz mono AAC
/// (~30–60 KB for 6 s — fast upload, Scribe-native sample rate).
final class QueryAudioRecorder {
  private var recorder: AVAudioRecorder?

  /// Output path. Reused for each call (overwritten on every record).
  private let outputURL: URL = FileManager.default
    .temporaryDirectory
    .appendingPathComponent("echo-query.m4a")

  /// Records up to `maxSeconds` and returns the file URL when finished.
  /// The recorder stops automatically at the cap; future improvement: add
  /// silence-detection cutoff for shorter queries.
  func record(maxSeconds: Double = 6.0) async throws -> URL {
    try await requestMicPermission()
    try configureSession()

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
      AVEncoderBitRateKey: 32000
    ]

    let recorder: AVAudioRecorder
    do {
      recorder = try AVAudioRecorder(url: outputURL, settings: settings)
    } catch {
      throw QueryAudioRecorderError.recorderInitFailed(error.localizedDescription)
    }
    recorder.isMeteringEnabled = false

    self.recorder = recorder
    let started = recorder.record(forDuration: maxSeconds)
    guard started else {
      self.recorder = nil
      throw QueryAudioRecorderError.recordFailed("recorder.record() returned false")
    }

    // Wait the cap, then stop + return. (`AVAudioRecorder` already stops itself
    // at the duration limit; we still call `stop()` for determinism.)
    try await Task.sleep(nanoseconds: UInt64(maxSeconds * 1_000_000_000))
    recorder.stop()
    self.recorder = nil

    return outputURL
  }

  func stop() {
    recorder?.stop()
    recorder = nil
  }

  // MARK: - Private

  private func requestMicPermission() async throws {
    let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard granted else {
      throw QueryAudioRecorderError.microphoneDenied
    }
  }

  private func configureSession() throws {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .measurement,
        options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      throw QueryAudioRecorderError.sessionConfigFailed(error.localizedDescription)
    }
  }
}
