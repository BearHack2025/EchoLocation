import ARKit
import ExpoModulesCore
import SceneKit
import UIKit

/// Render-only view that attaches an `ARSCNView` to the live `ARSession`
/// owned by `EchoLidarSession`, and renders ARMeshAnchors as colored wireframe.
/// Never calls `run()` / `pause()` — the session lifecycle stays with the controller.
public final class EchoLidarPreviewView: ExpoView, ARSCNViewDelegate {
  let scnView = ARSCNView(frame: .zero)

  /// One SCNNode per mesh anchor UUID so we can update / remove cleanly.
  private var anchorNodes: [UUID: SCNNode] = [:]

  /// Throttle `didUpdate`: skip refresh if last update was <0.1s ago for that anchor.
  private var lastUpdateAt: [UUID: TimeInterval] = [:]
  private let updateThrottleSeconds: TimeInterval = 0.1

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    scnView.translatesAutoresizingMaskIntoConstraints = false
    scnView.automaticallyUpdatesLighting = true
    scnView.autoenablesDefaultLighting = true
    scnView.backgroundColor = .black
    scnView.delegate = self
    addSubview(scnView)
    NSLayoutConstraint.activate([
      scnView.topAnchor.constraint(equalTo: topAnchor),
      scnView.bottomAnchor.constraint(equalTo: bottomAnchor),
      scnView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scnView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    attachSharedSessionIfNeeded()
  }

  private func attachSharedSessionIfNeeded() {
    guard
      window != nil,
      let module = EchoLidarModule.current
    else {
      return
    }
    let shared = module.session.sharedARSession
    if scnView.session !== shared {
      scnView.session = shared
    }
  }

  // MARK: - ARSCNViewDelegate (mesh wireframe overlay)

  public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let mesh = anchor as? ARMeshAnchor else { return }
    // ARSCNView already positions `node` at anchor.transform. Attach a child
    // with identity transform so the geometry rides the parent's pose.
    let wireframe = SCNNode()
    wireframe.geometry = MeshAnchorRenderer.makeGeometry(for: mesh)
    node.addChildNode(wireframe)
    anchorNodes[mesh.identifier] = wireframe
    lastUpdateAt[mesh.identifier] = CACurrentMediaTime()
  }

  public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    guard let mesh = anchor as? ARMeshAnchor else { return }
    let now = CACurrentMediaTime()
    if let last = lastUpdateAt[mesh.identifier], now - last < updateThrottleSeconds {
      return
    }
    lastUpdateAt[mesh.identifier] = now

    if let existing = anchorNodes[mesh.identifier] {
      existing.geometry = MeshAnchorRenderer.makeGeometry(for: mesh)
    }
  }

  public func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    guard let mesh = anchor as? ARMeshAnchor else { return }
    anchorNodes[mesh.identifier]?.removeFromParentNode()
    anchorNodes.removeValue(forKey: mesh.identifier)
    lastUpdateAt.removeValue(forKey: mesh.identifier)
  }
}
