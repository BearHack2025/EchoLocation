import AVFoundation
import Foundation
import simd

/// Plays a short HRTF-spatialized ping continuously, positioned at the
/// nearest obstacle in world space. Pitch scales with distance so closer
/// obstacles sound higher, while cadence stays effectively constant.
final class SpatialPingPlayer {
  private let engine = AVAudioEngine()
  private let environment = AVAudioEnvironmentNode()
  private let player = AVAudioPlayerNode()

  private var pingBuffer: AVAudioPCMBuffer?
  private var engineConfigured = false
  private var currentFrequency: Float?
  private var currentPulseRate: Float?

  private var listenerTransform: simd_float4x4 = matrix_identity_float4x4
  private var emitterWorldPoint: SIMD3<Float>?
  private var emitterDistance: Float?

  private var muted: Bool = false
  private var running: Bool = false

  private let sampleRate: Double = 44_100
  private let loopDurationSec: Double = 1.0
  private let baseFrequency: Float = 880
  private let defaultDistanceMeters: Float = 1.5

  func start() {
    guard !running else { return }
    ensureAudioSession()
    setupEngine()
    do {
      try engine.start()
    } catch {
      print("[SpatialPingPlayer] engine start failed: \(error)")
      return
    }
    running = true
    updatePlayerPosition()
    refreshLoopingBuffer(force: true)
  }

  func stop() {
    player.stop()
    player.reset()
    engine.stop()
    currentFrequency = nil
    currentPulseRate = nil
    running = false
  }

  func setMuted(_ muted: Bool) {
    self.muted = muted
    player.volume = muted ? 0 : 1
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
    refreshLoopingBuffer()
  }

  // MARK: Private

  private func setupEngine() {
    guard !engineConfigured else { return }
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
    engineConfigured = true
  }

  private func refreshLoopingBuffer(force: Bool = false) {
    guard running else { return }
    ensureAudioSession()
    ensurePlaybackChain()
    let frequency = pitch(forDistance: emitterDistance)
    let pulseRate = pulseRate(forDistance: emitterDistance)

    if !force,
       let currentFrequency,
       let currentPulseRate,
       abs(currentFrequency - frequency) < 25,
       abs(currentPulseRate - pulseRate) < 0.25,
       pingBuffer != nil {
      return
    }

    guard let loopBuffer = synthesizeLoopingPing(frequency: frequency, pulseRate: pulseRate) else { return }
    pingBuffer = loopBuffer
    currentFrequency = frequency
    currentPulseRate = pulseRate

    player.stop()
    player.reset()
    player.scheduleBuffer(loopBuffer, at: nil, options: .loops, completionHandler: nil)
    player.volume = muted ? 0 : 1
    player.play()
  }

  private func pitch(forDistance distance: Float?) -> Float {
    guard let d = distance else { return 1_000 }
    // Closer = higher pitch: 1320 Hz at 0.5m, 660 Hz at 5m.
    let clamped = max(0.5, min(5.0, d))
    let t = (clamped - 0.5) / 4.5
    return 1320 - Float(t) * 660
  }

  private func pulseRate(forDistance distance: Float?) -> Float {
    guard let d = distance else { return 4.8 }
    let clamped = max(0.5, min(5.0, d))
    let t = (clamped - 0.5) / 4.5
    return 6.0 - Float(t) * 2.5
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

  private func synthesizeLoopingPing(frequency: Float, pulseRate: Float) -> AVAudioPCMBuffer? {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * loopDurationSec)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
    buffer.frameLength = frameCount

    let samples = buffer.floatChannelData![0]
    let twoPiF = 2 * Float.pi * frequency
    let twoPiPulse = 2 * Float.pi * pulseRate
    let sr = Float(sampleRate)

    for i in 0..<Int(frameCount) {
      let t = Float(i) / sr
      let pulseShape = max(0, sinf(twoPiPulse * t))
      let envelope = 0.22 + (powf(pulseShape, 1.35) * 0.78)
      samples[i] = sinf(twoPiF * t) * envelope * 0.45
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

    if !player.isPlaying, pingBuffer != nil {
      player.play()
    }
  }
}
