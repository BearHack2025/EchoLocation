import ARKit
import ExpoModulesCore

public final class EchoLidarModule: Module {
  private let sessionController = EchoLidarSession()

  public func definition() -> ModuleDefinition {
    Name("EchoLidar")

    Events("onEchoUpdate")

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
  }
}
