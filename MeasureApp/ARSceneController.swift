//
//  ARSceneController.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/13.
//

import UIKit
import ARKit
import SceneKit

enum DrawFunction {
    case line
    case square
}

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

    private var isPlaneDetected: Bool = false
    
    
    // 状态变量
    private var isDrawing = false
    private var startLocation: SCNVector3? // 起点
    private var dashedLineNodes: [SCNNode] = [] // 当前绘制的虚线点
    
    // 1. 每个线段的起始点位置（测面积）
    // 2. 每个线段的起始点和终点位置（测距离）
    private var allSidePoints: [SCNVector3] = [] {
        didSet {
            switch drawFunction {
            case .line:
                // 测距离模式，结束绘制后，把直线的两头作为可吸附的 node
                if !isDrawing {
                    lineEndPoints.append(contentsOf: allSidePoints)
                }
            case .square:
                // 测面积模式，超过两条线段，则把第一个起始点作为可吸附的 node
                guard allSidePoints.count >= 3, let firstPoint = allSidePoints.first else { return }
                lineEndPoints.append(firstPoint)
            }
        }
    }
    
    private var finishedDashedLines: [[SCNNode]] = [] // 已完成的虚线集合
    private var lineEndPoints: [SCNVector3] = []
    
    private var drawFunction: DrawFunction = .square
    
    
    
    // 是否已经吸附了，防止震动反馈多次
    private var isAdsorption: Bool = false
    
    private lazy var addObjectButton: UIButton = {
        let button = UIButton()
        button.backgroundColor = UIColor.systemPink;
        button.addTarget(self, action: #selector(stopDrawing), for: .touchUpInside)
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
    private func stopDrawing() {
        finishDrawing()
    }
    
    @objc
    private func tapAction(_ gesture: UITapGestureRecognizer) {
        
        if drawFunction == .square {
            
            // 如果起始点和终点重合就停止绘制
//            if let startNode = self.dashedLineNodes.first,
//               let endNode = self.dashedLineNodes.last {
//                
//            }
            // 开始新的虚线绘制
            startDrawing()
        } else {
            if isDrawing {
                // 结束绘制虚线
                finishDrawing()
            } else {
                // 开始新的虚线绘制
                startDrawing()
            }
        }
    }
    
    private func startDrawing() {
        isDrawing = true
        guard let hitTestResult = sceneView.smartHitTest(sceneView.center) else { return }
        startLocation = SCNVector3(hitTestResult.worldTransform.translation)
        
        guard let startLocation = startLocation else { return }
        let initialEndLocation = startLocation

        if drawFunction == .line {
            clearDashedLine()
        }
//        clearDashedLine()
        
        allSidePoints.append(startLocation)
        dashedLineNodes = createDashedLine(from: startLocation, to: initialEndLocation, interval: 0.01, radius: 0.002, color: .white)
//        if let firstNode = dashedLineNodes.first {
//            lineSidePoints.append(firstNode.position)
//        }
        
        for node in dashedLineNodes {
            sceneView.scene.rootNode.addChildNode(node)
        }
    }

    // 结束绘制虚线
    private func finishDrawing() {
        // 将当前虚线保存到已完成虚线集合
        finishedDashedLines.append(dashedLineNodes)
        
        // 结束点
        if let lastNode = dashedLineNodes.last {
            lineEndPoints.append(lastNode.position)
        }
        
        dashedLineNodes = []
        isDrawing = false
    }
    
    
    // MARK: - 创建虚线起点
    private func createDashedLine(from start: SCNVector3, to end: SCNVector3, interval: Float, radius: CGFloat, color: UIColor) -> [SCNNode] {
        var nodes: [SCNNode] = []
        let vector = SCNVector3(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z)
        let distance = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)

        guard distance > 0 else {
            // 一开始 起点和终点相同的话只绘制一个点 起始点
            let sphere = SCNSphere(radius: radius)
            sphere.firstMaterial?.diffuse.contents = color
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = start
            nodes.append(sphereNode)
            return nodes
        }

        let direction = vector.normalized()
        var currentPosition = start

        while (currentPosition - start).length() < distance {
            let sphere = SCNSphere(radius: radius)
            sphere.firstMaterial?.diffuse.contents = color
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = currentPosition
            nodes.append(sphereNode)

            // 按间隔更新位置
            currentPosition.x += direction.x * interval
            currentPosition.y += direction.y * interval
            currentPosition.z += direction.z * interval
        }

        return nodes
    }

    // MARK: -  camera 移动的时候动态更新虚线
    private func updateDashedLine(to endLocation: SCNVector3) {
        guard let startLocation = startLocation else { return }

        // 1. 先清除旧虚线
        clearDashedLine()

        // 2. 创建新的虚线
        dashedLineNodes = createDashedLine(from: startLocation, to: endLocation, interval: 0.01, radius: 0.002, color: .white)
        for node in dashedLineNodes {
            sceneView.scene.rootNode.addChildNode(node)
        }
    }
    
    // MARK: - 清楚旧的虚线
    private func clearDashedLine() {
        for node in dashedLineNodes {
            node.removeFromParentNode()
        }
        dashedLineNodes.removeAll()
    }
    
    
    private func checkSnapToLineEndpoints(centerPosition:SCNVector3, lineEndpoints: [SCNVector3]) {
        let focusPosition = centerPosition//focusSquare.centerNode.worldPosition
        
        // 吸附范围
        let snapRange: Float = 0.05// 5cm
        
        for endpoint in lineEndpoints {
            let distance = focusPosition.distance(to: endpoint)
            if distance <= snapRange {
                // 小于 5cm 自动吸附
                snapToEndpoint(focusSquare: focusSquare, endpoint: endpoint)
            } else {
                // 大于 5cm 回到初始位置
                resetFocusSquareCenter(focusSquare: focusSquare)
            }
        }
    }
    
    private func snapToEndpoint(focusSquare: FocusSquare, endpoint: SCNVector3) {
        focusSquare.centerNode.worldPosition = endpoint
        if !isAdsorption {
            // 吸附到端点
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            isAdsorption = true
            updateDashedLine(to: endpoint)
        }
    }
    
    private func resetFocusSquareCenter(focusSquare: FocusSquare) {
        let initialPosition = SIMD3<Float>(0, 0.005, 0)
        focusSquare.centerNode.simdPosition = initialPosition
        if isAdsorption {
            // 直接设置位置为初始位置
            isAdsorption = false
        }
    }

}

extension ARSceneController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.updateFocusSquare(isObjectVisible: false)
            if !self.lineEndPoints.isEmpty {
                let screenCenter = self.sceneView.screenCenter
                guard let hitTestResult = self.sceneView.smartHitTest(screenCenter) else { return }
                self.checkSnapToLineEndpoints(centerPosition: SCNVector3(hitTestResult.worldTransform.translation), lineEndpoints: self.lineEndPoints)
            }
        }
        
        DispatchQueue.main.async {
            let screenCenter = self.sceneView.screenCenter
            guard let hitTestResult = self.sceneView.smartHitTest(screenCenter), !self.dashedLineNodes.isEmpty else { return }
            let endLocation = SCNVector3(hitTestResult.worldTransform.translation)
            // 如果已经吸附了就不让他主动更新
            if !self.isAdsorption {
                self.updateDashedLine(to: endLocation)
            }
            
        }
    }
    
    func renderer(_ renderer: any SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        if planeAnchor.alignment == .horizontal || planeAnchor.alignment == .vertical {
            isPlaneDetected = true
        }
    }
    
    func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
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

