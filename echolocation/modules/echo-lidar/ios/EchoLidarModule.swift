import ARKit
import ExpoModulesCore

public final class EchoLidarModule: Module {
  /// Weak reference so the preview view can find the live module instance
  /// to attach its ARSCNView to the same ARSession that drives EchoUpdate events.
  public static weak var current: EchoLidarModule?

  private let sessionController = EchoLidarSession()
  private let voiceCommandController = VoiceCommandController()

  /// Exposed so EchoLidarPreviewView can attach to sharedARSession.
  var session: EchoLidarSession { sessionController }

  public func definition() -> ModuleDefinition {
    Name("EchoLidar")

    OnCreate { [weak self] in
      EchoLidarModule.current = self
    }

    Events("onEchoUpdate", "onVoiceCommand")

    View(EchoLidarPreviewView.self) {
      Prop("showHeatmap") { (view: EchoLidarPreviewView, value: Bool?) in
        view.showHeatmap = value ?? true
      }
    }

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
