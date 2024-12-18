//
//  ARSceneController.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/13.
//

import UIKit
import ARKit
import SceneKit

class ARSceneController: UIViewController {

    public lazy var sceneView: ARSCNView = {
        let sceneView = ARSCNView(frame: view.bounds)
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        return sceneView
    }()
    
    public lazy var session: ARSession = {
        return sceneView.session
    }()
        
    let coachingOverlay = ARCoachingOverlayView()
    
    var focusSquare = FocusSquare()

    /// A serial queue used to coordinate adding or removing nodes from the scene.
    let updateQueue = DispatchQueue(label: "com.example.apple-samplecode.arkitexample.serialSceneKitQueue")

    
    private lazy var addObjectButton: UIButton = {
        let button = UIButton()
        button.backgroundColor = UIColor.systemPink;
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
        setupCoachingOverlay()
        
        // Set up scene content.
        sceneView.scene.rootNode.addChildNode(focusSquare)

    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetTracking()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func setupSceneView() {
        view.backgroundColor = .white
        view.addSubview(sceneView)
        
        sceneView .addSubview(addObjectButton)
        addObjectButton.snp.makeConstraints { make in
            make.bottom.equalTo(sceneView).offset(-80)
            make.centerX.equalTo(sceneView)
            make.width.equalTo(80)
            make.height.equalTo(50)
        }
        
        // tap to place object
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapAction(_:)))
        sceneView.addGestureRecognizer(tapGesture)
    }
    
    private func setupCoachingOverlay() {
        coachingOverlay.session = sceneView.session
        coachingOverlay.delegate = self
        
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        sceneView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coachingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            coachingOverlay.widthAnchor.constraint(equalTo: view.widthAnchor),
            coachingOverlay.heightAnchor.constraint(equalTo: view.heightAnchor)
            ])
        
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.goal = .anyPlane
    }
    
    
    // MARK: - Focus Square

    func updateFocusSquare(isObjectVisible: Bool) {
        if isObjectVisible || coachingOverlay.isActive {
            focusSquare.hide()
        } else {
            focusSquare.unhide()
            //提示
            //statusViewController.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
        }
        
        // Perform ray casting only when ARKit tracking is in a good state.
        if let camera = session.currentFrame?.camera, case .normal = camera.trackingState,
            let query = sceneView.getRaycastQuery(),
            let result = sceneView.castRay(for: query).first {
            
            updateQueue.async {
                self.sceneView.scene.rootNode.addChildNode(self.focusSquare)
                self.focusSquare.state = .detecting(raycastResult: result, camera: camera)
            }
            if !coachingOverlay.isActive {
                addObjectButton.isHidden = false
            }
            //提示
            //statusViewController.cancelScheduledMessage(for: .focusSquare)
        } else {
            updateQueue.async {
                self.focusSquare.state = .initializing
                self.sceneView.pointOfView?.addChildNode(self.focusSquare)
            }
            addObjectButton.isHidden = true
            //提示
            //objectsViewController?.dismiss(animated: false, completion: nil)
        }
    }
    
    @objc
    private func tapAction(_ gesture: UITapGestureRecognizer) {
        
    }

}

extension ARSceneController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.updateFocusSquare(isObjectVisible: false)
        }
    }
    
    func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
//        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
//        if planeAnchor.alignment == .horizontal || planeAnchor.alignment == .vertical {
//            print("找到平面了1")
//            canPlaceObject = true
//        }
        
//        DispatchQueue.main.async {
//            guard self.placedObjectOnPlane == false else { return }
//            let touchLocation = self.sceneView.screenCenter
//            guard let hitTestResult = self.sceneView.smartHitTest(touchLocation) else { return }
//            self.addFocusNodeWithPosition(hitTestResult.worldTransform.translation)
//            self.placedObjectOnPlane = true
//        }
    }
    
    func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
//        guard let planeAnchor = anchor as? ARPlaneAnchor, placedObjectOnPlane else { return }
//        if planeAnchor.alignment == .horizontal || planeAnchor.alignment == .vertical {
////            print("找到平面了2")
////            canPlaceObject = true
//            DispatchQueue.main.async {
//                let touchLocation = self.sceneView.screenCenter
//                guard let hitTestResult = self.sceneView.smartHitTest(touchLocation) else { return }
//                self.updateFocusNodeWithPosition(hitTestResult.worldTransform.translation)
//            }
//        }
        
        
    }
}

extension ARSceneController: ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .limited(.initializing):
            print("初始化")
        case .limited(.excessiveMotion):
            print("过度移动")
        case .limited(.insufficientFeatures):
            print("缺少特征点")
        case .limited(.relocalizing):
            print("再次本地化")
        case .limited(_):
            print("未知原因")
        case .notAvailable:
            print("Tracking不可用")
        case .normal:
            print("正常")
    
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Hide content before going into the background.
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
}

extension ARSceneController: ARCoachingOverlayViewDelegate {
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
    }
    
    // PresentUI
    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
    }

    // StartOver
    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
    }
}


extension ARSCNView {
//    func smartHitTest(_ point: CGPoint) -> raycast? {
//
//        // Perform the hit test.
//        let results = hitTest(point, types: [.existingPlaneUsingGeometry])
//        
//        // 1. Check for a result on an existing plane using geometry.
//        if let existingPlaneUsingGeometryResult = results.first(where: { $0.type == .existingPlaneUsingGeometry }) {
//            return existingPlaneUsingGeometryResult
//        }
//        
//        // 2. Check for a result on an existing plane, assuming its dimensions are infinite.
//        let infinitePlaneResults = hitTest(point, types: .existingPlaneUsingExtent)
//        
//        if let infinitePlaneResult = infinitePlaneResults.first {
//            return infinitePlaneResult
//        }
//        
//        // 3. As a final fallback, check for a result on estimated planes.
//        return results.first(where: { $0.type == .estimatedHorizontalPlane })
//    }
    func smartHitTest(_ point: CGPoint) -> ARRaycastResult? {
        // 1. Create a raycast query for existing plane geometry.
        if let query = raycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .any),
           let result = session.raycast(query).first {
            return result
        }
        
        // 2. Create a raycast query for infinite planes.
        if let query = raycastQuery(from: point, allowing: .existingPlaneInfinite, alignment: .any),
           let result = session.raycast(query).first {
            return result
        }
        
        // 3. Create a raycast query for estimated horizontal planes.
        if let query = raycastQuery(from: point, allowing: .estimatedPlane, alignment: .horizontal),
           let result = session.raycast(query).first {
            return result
        }
        
        return nil
    }
    
    /**
     Type conversion wrapper for original `unprojectPoint(_:)` method.
     Used in contexts where sticking to SIMD3<Float> type is helpful.
     */
    func unprojectPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(unprojectPoint(SCNVector3(point)))
    }
    
    // - Tag: CastRayForFocusSquarePosition
    func castRay(for query: ARRaycastQuery) -> [ARRaycastResult] {
        return session.raycast(query)
    }

    // - Tag: GetRaycastQuery
    func getRaycastQuery(for alignment: ARRaycastQuery.TargetAlignment = .any) -> ARRaycastQuery? {
        return raycastQuery(from: screenCenter, allowing: .estimatedPlane, alignment: alignment)
    }
    
    
    var screenCenter: CGPoint {
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

extension float4x4 {
    var translation: SIMD3<Float> {
        get {
            let translation = columns.3
            return [translation.x, translation.y, translation.z]
        }
        set(newValue) {
            columns.3 = [newValue.x, newValue.y, newValue.z, columns.3.w]
        }
    }

    var orientation: simd_quatf {
        return simd_quaternion(self)
    }

    init(uniformScale scale: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scale
        columns.1.y = scale
        columns.2.z = scale
    }
}

