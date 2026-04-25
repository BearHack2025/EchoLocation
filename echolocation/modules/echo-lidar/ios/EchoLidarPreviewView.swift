import ARKit
import ExpoModulesCore
import SceneKit
import UIKit

/// Render-only view that attaches an `ARSCNView` to the live `ARSession`
/// owned by `EchoLidarSession`, and renders ARMeshAnchors as a two-layer
/// distance heatmap + classification outline. The mesh anchor at the screen
/// center gets a brightening "targeted" emission boost.
///
/// Never calls `run()` / `pause()` — the session lifecycle stays with the
/// controller; this view is purely a viewport.
public final class EchoLidarPreviewView: ExpoView, ARSCNViewDelegate {
  let scnView = ARSCNView(frame: .zero)

  /// Fill (heatmap) + outline (classification color) per ARMeshAnchor UUID.
  private struct AnchorNodes {
    let fill: SCNNode
    let outline: SCNNode
  }
  private var anchorNodes: [UUID: AnchorNodes] = [:]

  /// Throttle `didUpdate`: skip refresh if last update was <0.1s ago for that anchor.
  private var lastUpdateAt: [UUID: TimeInterval] = [:]
  private let updateThrottleSeconds: TimeInterval = 0.1

  /// Anchor currently highlighted at the screen center (if any).
  private var targetedAnchorId: UUID?
  /// 200ms hysteresis: only swap the targeted anchor when the new candidate
  /// has been stable for at least this long.
  private var pendingTargetId: UUID?
  private var pendingTargetSince: TimeInterval = 0
  private let targetHysteresisSeconds: TimeInterval = 0.2

  /// Bound to the JS prop `showHeatmap`. When false, the fill layer hides
  /// and the view falls back to the Phase 3 outline-only look.
  public var showHeatmap: Bool = true {
    didSet { applyShowHeatmap() }
  }

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

  private func applyShowHeatmap() {
    let hidden = !showHeatmap
    for pair in anchorNodes.values {
      pair.fill.isHidden = hidden
    }
  }

  // MARK: - ARSCNViewDelegate (mesh layers)

  public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let mesh = anchor as? ARMeshAnchor else { return }

    // ARSCNView positions `node` at anchor.transform; both layers ride the
    // parent's pose with identity transforms.
    let fillNode = SCNNode()
    fillNode.geometry = MeshAnchorRenderer.makeFillGeometry(for: mesh)
    fillNode.isHidden = !showHeatmap

    let outlineNode = SCNNode()
    outlineNode.geometry = MeshAnchorRenderer.makeOutlineGeometry(for: mesh)
    // Tag the outline so the screen-center hit test maps back to the anchor.
    outlineNode.name = mesh.identifier.uuidString

    node.addChildNode(fillNode)
    node.addChildNode(outlineNode)
    anchorNodes[mesh.identifier] = AnchorNodes(fill: fillNode, outline: outlineNode)
    lastUpdateAt[mesh.identifier] = CACurrentMediaTime()
  }

  public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    guard let mesh = anchor as? ARMeshAnchor else { return }
    let now = CACurrentMediaTime()
    if let last = lastUpdateAt[mesh.identifier], now - last < updateThrottleSeconds {
      return
    }
    lastUpdateAt[mesh.identifier] = now

    if let pair = anchorNodes[mesh.identifier] {
      pair.fill.geometry = MeshAnchorRenderer.makeFillGeometry(for: mesh)
      pair.outline.geometry = MeshAnchorRenderer.makeOutlineGeometry(for: mesh)
      // didUpdate may rebuild the outline material, wiping any glow we set
      // last frame. Re-apply if this anchor is still the target.
      if targetedAnchorId == mesh.identifier {
        applyTargetGlow(to: pair, on: true)
      }
    }
  }

  public func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    guard let mesh = anchor as? ARMeshAnchor else { return }
    anchorNodes[mesh.identifier]?.fill.removeFromParentNode()
    anchorNodes[mesh.identifier]?.outline.removeFromParentNode()
    anchorNodes.removeValue(forKey: mesh.identifier)
    lastUpdateAt.removeValue(forKey: mesh.identifier)
    if targetedAnchorId == mesh.identifier {
      targetedAnchorId = nil
    }
    if pendingTargetId == mesh.identifier {
      pendingTargetId = nil
    }
  }

  // MARK: - Targeted highlight (per-frame)

  public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    let bounds = scnView.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }

    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let hits = scnView.hitTest(
      center,
      options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue]
    )
    let hitId = hits
      .lazy
      .compactMap { $0.node.name.flatMap(UUID.init(uuidString:)) }
      .first(where: { anchorNodes[$0] != nil })

    // Hysteresis: candidate must be stable for `targetHysteresisSeconds`
    // before we promote it. This kills flicker between adjacent anchors.
    if hitId != pendingTargetId {
      pendingTargetId = hitId
      pendingTargetSince = time
      return
    }
    guard time - pendingTargetSince >= targetHysteresisSeconds else { return }

    if hitId != targetedAnchorId {
      if let prev = targetedAnchorId, let pair = anchorNodes[prev] {
        applyTargetGlow(to: pair, on: false)
      }
      if let next = hitId, let pair = anchorNodes[next] {
        applyTargetGlow(to: pair, on: true)
      }
      targetedAnchorId = hitId
    }
  }

  private func applyTargetGlow(to pair: AnchorNodes, on: Bool) {
    let material = pair.outline.geometry?.firstMaterial
    material?.emission.contents = on ? UIColor(white: 1.0, alpha: 0.6) : UIColor.black
  }
}
