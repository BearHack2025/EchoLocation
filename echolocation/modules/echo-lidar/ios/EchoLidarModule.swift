import ARKit
import ExpoModulesCore

enum EchoLidarModuleError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "EchoLidar module is unavailable."
    }
  }
}

public final class EchoLidarModule: Module {
  private let sessionController = EchoLidarSession()
  private let voiceCommandController = VoiceCommandController()

  public func definition() -> ModuleDefinition {
    Name("EchoLidar")

    Events("onEchoUpdate", "onVoiceCommand")

    Function("isSupported") {
      ARWorldTrackingConfiguration.isSupported
    }

    Function("supportsDepth") {
      ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth])
    }

    Function("supportsMeshClassification") {
      ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    Function("getSupportStatus") {
      return [
        "isARSupported": ARWorldTrackingConfiguration.isSupported,
        "supportsDepth": ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]),
        "supportsMeshClassification": ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
      ]
    }

    AsyncFunction("start") { [weak self] (mode: String?) in
      guard let self else {
        return
      }

      try self.sessionController.start(
        mode: mode ?? "describe",
        sendEvent: { name, payload in
          self.sendEvent(name, payload)
        }
      )
    }

    AsyncFunction("stop") { [weak self] in
      self?.sessionController.stop()
    }

    AsyncFunction("captureSnapshot") { [weak self] () -> [String: Any] in
      guard let self else {
        throw EchoLidarModuleError.unavailable
      }

      return try await MainActor.run {
        try self.sessionController.captureSnapshot()
      }
    }

    AsyncFunction("captureAndLabelScene") { [weak self] () -> [String: Any] in
      guard let self else {
        throw EchoLidarModuleError.unavailable
      }

      return try await MainActor.run {
        try self.sessionController.captureAndLabelScene()
      }
    }

    AsyncFunction("startVoiceCommands") { [weak self] in
      guard let self else {
        return
      }

      try await self.voiceCommandController.startListening { payload in
        self.sendEvent("onVoiceCommand", payload)
      }
    }

    AsyncFunction("stopVoiceCommands") { [weak self] in
      await MainActor.run {
        self?.voiceCommandController.stopListening()
      }
    }
  }
}
