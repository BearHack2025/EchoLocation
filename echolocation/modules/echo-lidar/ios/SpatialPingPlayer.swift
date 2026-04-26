import AVFoundation
import Foundation
import simd

/// Plays a short HRTF-spatialized ping continuously, positioned at the
/// nearest obstacle in world space. The tone stays fixed while the
/// repeat interval gets shorter as obstacles get closer.
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
  private var lastPingAt: TimeInterval = 0

  private let sampleRate: Double = 44_100
  private let pingDurationSec: Double = 0.18
  private let baseFrequency: Float = 880
  private let defaultDistanceMeters: Float = 1.5
  private let defaultPingIntervalSec: TimeInterval = 0.24
  private let minPingIntervalSec: TimeInterval = 0.18
  private let maxPingIntervalSec: TimeInterval = 0.42
  private let timerResolutionSec: TimeInterval = 0.05

  func start() {
    guard !running else { return }
    ensureAudioSession()
    setupEngine()
    pingBuffer = synthesizePing(frequency: baseFrequency)
    do {
      try engine.start()
    } catch {
      print("[SpatialPingPlayer] engine start failed: \(error)")
      return
    }
    ensurePlaybackChain()
    running = true
    schedulePings()
    emitPing()
  }

  func stop() {
    pingTimer?.invalidate()
    pingTimer = nil
    player.stop()
    engine.stop()
    lastPingAt = 0
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
    updatePlayerPosition()
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
    let timer = Timer.scheduledTimer(withTimeInterval: timerResolutionSec, repeats: true) { [weak self] _ in
      self?.tickIfDue()
    }
    timer.tolerance = timerResolutionSec * 0.2
    pingTimer = timer
  }

  private func tickIfDue() {
    guard running, !muted else { return }
    let now = CACurrentMediaTime()
    guard now - lastPingAt >= currentPingInterval() else { return }
    emitPing(at: now)
  }

  private func emitPing(at timestamp: TimeInterval = CACurrentMediaTime()) {
    guard running, !muted, let buffer = pingBuffer else { return }
    lastPingAt = timestamp
    ensureAudioSession()
    ensurePlaybackChain()
    updatePlayerPosition()
    player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
  }

  private func currentPingInterval() -> TimeInterval {
    guard let distance = emitterDistance else {
      return defaultPingIntervalSec
    }

    let clampedDistance = max(0.4, min(4.0, distance))
    let normalized = (clampedDistance - 0.4) / 3.6
    return minPingIntervalSec + (TimeInterval(normalized) * (maxPingIntervalSec - minPingIntervalSec))
  }

  private func updatePlayerPosition() {
    let worldPoint = emitterWorldPoint ?? defaultEmitterWorldPoint()
    player.position = AVAudio3DPoint(x: worldPoint.x, y: worldPoint.y, z: worldPoint.z)
  }

  private func defaultEmitterWorldPoint() -> SIMD3<Float> {
    let origin = SIMD3<Float>(
      listenerTransform.columns.3.x,
      listenerTransform.columns.3.y,
      listenerTransform.columns.3.z
    )
    let forward = simd_normalize(
      SIMD3<Float>(
        -listenerTransform.columns.2.x,
        -listenerTransform.columns.2.y,
        -listenerTransform.columns.2.z
      )
    )
    return origin + (forward * defaultDistanceMeters)
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

  private func ensureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()

    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth, .allowBluetoothA2DP]
      )
      try audioSession.setActive(true)
    } catch {
      print("[SpatialPingPlayer] audio session error: \(error)")
    }
  }

  private func ensurePlaybackChain() {
    if !engine.isRunning {
      do {
        try engine.start()
      } catch {
        print("[SpatialPingPlayer] engine restart failed: \(error)")
      }
    }

    if !player.isPlaying {
      player.play()
    }
  }
}
