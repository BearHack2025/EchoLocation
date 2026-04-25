import AVFoundation
import Foundation
import simd

/// Plays a short HRTF-spatialized "ping" once per second, positioned at the
/// nearest obstacle in world space. Pitch + cadence scale with distance so
/// closer obstacles ping faster and higher.
final class SpatialPingPlayer {
  private let engine = AVAudioEngine()
  private let environment = AVAudioEnvironmentNode()
  private let player = AVAudioPlayerNode()

  private var pingBuffer: AVAudioPCMBuffer?
  private var pingTimer: Timer?

  private var listenerTransform: simd_float4x4 = matrix_identity_float4x4
  private var emitterWorldPoint: SIMD3<Float>?
  private var emitterDistance: Float?

  private var muted: Bool = false
  private var running: Bool = false

  private let sampleRate: Double = 44_100
  private let pingDurationSec: Double = 0.06
  private let baseFrequency: Float = 880

  func start() {
    guard !running else { return }
    setupEngine()
    pingBuffer = synthesizePing(frequency: baseFrequency)
    do {
      try engine.start()
    } catch {
      print("[SpatialPingPlayer] engine start failed: \(error)")
      return
    }
    player.play()
    running = true
    schedulePings()
  }

  func stop() {
    pingTimer?.invalidate()
    pingTimer = nil
    player.stop()
    engine.stop()
    running = false
  }

  func setMuted(_ muted: Bool) {
    self.muted = muted
  }

  func updateListener(transform: simd_float4x4) {
    listenerTransform = transform
    let pos = AVAudio3DPoint(
      x: transform.columns.3.x,
      y: transform.columns.3.y,
      z: transform.columns.3.z
    )
    environment.listenerPosition = pos

    // Forward = -Z column, Up = +Y column of camera transform.
    let forward = SIMD3<Float>(-transform.columns.2.x,
                               -transform.columns.2.y,
                               -transform.columns.2.z)
    let up = SIMD3<Float>(transform.columns.1.x,
                          transform.columns.1.y,
                          transform.columns.1.z)
    environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
      forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
      up: AVAudio3DVector(x: up.x, y: up.y, z: up.z)
    )
  }

  func updateEmitter(worldPoint: SIMD3<Float>?, distance: Float?) {
    emitterWorldPoint = worldPoint
    emitterDistance = distance
    if let worldPoint {
      player.position = AVAudio3DPoint(x: worldPoint.x, y: worldPoint.y, z: worldPoint.z)
    }
  }

  // MARK: Private

  private func setupEngine() {
    environment.renderingAlgorithm = .HRTFHQ
    environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
    environment.distanceAttenuationParameters.referenceDistance = 0.5
    environment.distanceAttenuationParameters.maximumDistance = 8.0
    environment.distanceAttenuationParameters.rolloffFactor = 1.2

    engine.attach(environment)
    engine.attach(player)

    let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    engine.connect(player, to: environment, format: monoFormat)
    engine.connect(environment, to: engine.mainMixerNode, format: nil)

    player.renderingAlgorithm = .HRTFHQ
    player.sourceMode = .pointSource
  }

  private func schedulePings() {
    pingTimer?.invalidate()
    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      self?.tickIfDue()
    }
    RunLoop.main.add(timer, forMode: .common)
    pingTimer = timer
  }

  private var lastPingAt: TimeInterval = 0

  private func tickIfDue() {
    guard running, !muted, let buffer = pingBuffer, emitterWorldPoint != nil else { return }
    let now = CACurrentMediaTime()
    let interval = pingInterval(forDistance: emitterDistance)
    guard now - lastPingAt >= interval else { return }
    lastPingAt = now

    // Re-synthesize buffer if pitch should change with distance.
    let frequency = pitch(forDistance: emitterDistance)
    if let scaled = synthesizePing(frequency: frequency) {
      player.scheduleBuffer(scaled, at: nil, options: .interrupts, completionHandler: nil)
    } else {
      player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
  }

  private func pingInterval(forDistance distance: Float?) -> TimeInterval {
    guard let d = distance else { return 1.0 }
    // Closer = faster pings: 0.3s at 0.5m, 1.5s at 5m.
    let clamped = max(0.5, min(5.0, d))
    let t = (clamped - 0.5) / 4.5
    return 0.3 + Double(t) * 1.2
  }

  private func pitch(forDistance distance: Float?) -> Float {
    guard let d = distance else { return baseFrequency }
    // Closer = higher pitch: 1320 Hz at 0.5m, 660 Hz at 5m.
    let clamped = max(0.5, min(5.0, d))
    let t = (clamped - 0.5) / 4.5
    return 1320 - Float(t) * 660
  }

  private func synthesizePing(frequency: Float) -> AVAudioPCMBuffer? {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * pingDurationSec)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
    buffer.frameLength = frameCount

    let samples = buffer.floatChannelData![0]
    let twoPiF = 2 * Float.pi * frequency
    let sr = Float(sampleRate)
    let totalFrames = Float(frameCount)

    // Sine with attack/decay envelope.
    for i in 0..<Int(frameCount) {
      let t = Float(i) / sr
      let progress = Float(i) / totalFrames
      let envelope: Float
      if progress < 0.1 {
        envelope = progress / 0.1
      } else {
        envelope = max(0, 1 - (progress - 0.1) / 0.9)
      }
      samples[i] = sinf(twoPiF * t) * envelope * 0.6
    }
    return buffer
  }
}
