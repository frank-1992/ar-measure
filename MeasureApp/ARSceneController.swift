//
//  ARSceneController.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/13.
//

import UIKit
import ARKit
import SceneKit

enum DrawMode {
    case line
    case polygon
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
    let updateQueue = DispatchQueue(label: "com.wuyi.test.serialSceneKitQueue")

    private var isPlaneDetected: Bool = false
    
    
    // 状态变量
    private var isDrawing = false
    private var startLocation: SCNVector3? // 起点
    private var endLocation: SCNVector3? // 终点
    private let dashLineManager = DashLineManager() // 集成 LineManager
    private var dashedLineNode: SCNNode? // 当前绘制的虚线
//    private var dashedLineNodes: [SCNNode] = [] // 当前绘制的虚线点
    private var previousDashedLineNode: SCNNode? // 前一个绘制的虚线点
    
    // 1. 每个线段的起始点位置（测面积）
    // 2. 每个线段的起始点和终点位置（测距离）
    private var allSidePoints: [SCNVector3] = [] {
        didSet {
            switch drawMode {
            case .line:
                // 测距离模式，结束绘制后，把直线的两头作为可吸附的 node
                if !isDrawing {
                    lineEndPoints.removeAll()
                    lineEndPoints.append(contentsOf: allSidePoints)
                }
            case .polygon:
                // 测面积模式，超过两条线段，则把第一个起始点作为可吸附的 node
                guard allSidePoints.count >= 3, let firstPoint = allSidePoints.first else { return }
                lineEndPoints.append(firstPoint)
            }
        }
    }
    
    private var finishedDashedLines: [SCNNode] = [] // 已完成的虚线集合
    private var lineEndPoints: [SCNVector3] = []
    
    private var drawMode: DrawMode = .line
    
    
    // 是否已经吸附了，防止震动反馈多次
    private var isAdsorption: Bool = false
    private var adsorptionPoint: SCNVector3? //当前动态判断的吸附点坐标 超过距离就为 nil
    private var startAdsorptionLocation: SCNVector3? // 从吸附点绘制的起点
    private var endAdsorptionLocation: SCNVector3? // 绘制过程中吸附到的点的位置，如果结束绘制，那么终点就是吸附点，并且不需要创建 endSphere，只需要画直线
    private var allLineNodes: [SCNNode] = []
    
    private lazy var addObjectButton: UIButton = {
        let button = UIButton()
        button.backgroundColor = UIColor.systemPink;
        button.addTarget(self, action: #selector(changeMode(sender:)), for: .touchUpInside)
        button.setTitle("line", for: .normal)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
        setupCoachingOverlay()
        
        // Set up scene content.
        sceneView.scene.rootNode.addChildNode(focusSquare)
//        let labelNode = createLabelNode(text: "19 cm", width: 0.1, height: 0.05)
//        labelNode.position = SCNVector3(0, 0, -0.2)
//        sceneView.scene.rootNode.addChildNode(labelNode)
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
    private func changeMode(sender: UIButton) {
        if drawMode == .line {
            drawMode = .polygon
            sender.setTitle("polygon", for: .normal)
        } else {
            drawMode = .line
            sender.setTitle("line", for: .normal)
        }
        
        if isDrawing {
            finishDrawing()
        }
        
        for lineNode in allLineNodes {
            lineNode.removeFromParentNode()
        }
        allLineNodes.removeAll()
        lineEndPoints.removeAll()
        allSidePoints.removeAll()
        resetFocusSquareCenter(focusSquare: focusSquare)
    }
    
    private func finishPolygon() {
        finishDrawing()
        lineEndPoints.removeAll()
        allSidePoints.removeAll()
        resetFocusSquareCenter(focusSquare: focusSquare)
    }
    
    @objc
    private func tapAction(_ gesture: UITapGestureRecognizer) {
        
        if drawMode == .polygon {
            
            // 如果起始点和终点重合就停止绘制
            if isAdsorption {
                finishPolygon()
            } else {
                // 开始新的虚线绘制
                startDrawing()
            }
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
        
        guard var startLocation = startLocation else { return }

        // 如果是吸附状态的话 用最后一个点当做起点
        if isAdsorption {
            if let lastPosition = adsorptionPoint {
                startLocation = lastPosition
                startAdsorptionLocation = lastPosition
                self.startLocation = lastPosition
            }
        }
        
        // 所有节点位置的集合
        allSidePoints.append(startLocation)
        dashedLineNode = SCNNode()
        if let dashedLineNode = dashedLineNode {
            sceneView.scene.rootNode.addChildNode(dashedLineNode)
        }
        
        if drawMode == .polygon {
            if let dashedLineNode = dashedLineNode {
                finishedDashedLines.append(dashedLineNode)
            }
            previousDashedLineNode?.removeFromParentNode()
            if allSidePoints.count >= 2 {
                let lastPoint = allSidePoints[allSidePoints.count - 1]
                let previousPoint = allSidePoints[allSidePoints.count - 2]
                
                let lineNode = createLineBetween(
                    point1: previousPoint,
                    point2: lastPoint,
                    color: .systemGreen,
                    thickness: 0.004
                )
                // 添加尺寸显示面板
                addLabelNode(to: lineNode, startPoint: previousPoint, endPoint: lastPoint)
                allLineNodes.append(lineNode)
                sceneView.scene.rootNode.addChildNode(lineNode)
            }
        }
        previousDashedLineNode = dashedLineNode
    }

    // 结束绘制虚线
    private func finishDrawing() {
        isDrawing = false
        // 将当前虚线保存到已完成虚线集合
        if let dashedLineNode = dashedLineNode {
            finishedDashedLines.append(dashedLineNode)
        }
        
        // 结束点
        if let endLocation = endLocation {
            lineEndPoints.append(endLocation)
            // 把所有的点加进 allSidePoints 里进行筛选操作
            allSidePoints.append(endLocation)
        }
        
        // 如果 allSidePoints.count 大于等于 2 ,那么最后一个点 n 和前一个点 n-1,绘制成直线
        if allSidePoints.count >= 2 {
            switch drawMode {
            case .line:
                if let previousPoint = startAdsorptionLocation {
                    var lastPoint = allSidePoints[allSidePoints.count - 1]
                    // 如果结束画线的终点是在吸附点上就赋值吸附点的位置
                    if let endAdsorptionLocation = endAdsorptionLocation {
                        lastPoint = endAdsorptionLocation
                    }
                    clearDashedLine()
                    
                    let lineNode = createLineBetween(
                        point1: previousPoint,
                        point2: lastPoint,
                        color: .systemGreen,
                        thickness: 0.004
                    )
                    // 添加尺寸显示面板
                    addLabelNode(to: lineNode, startPoint: previousPoint, endPoint: lastPoint)
                    allLineNodes.append(lineNode)
                    sceneView.scene.rootNode.addChildNode(lineNode)
                    
                    startAdsorptionLocation = nil
                    endAdsorptionLocation = nil
                } else {
                    let lastPoint = allSidePoints[allSidePoints.count - 1]
                    let previousPoint = allSidePoints[allSidePoints.count - 2]
                    clearDashedLine()
                    
                    let lineNode = createLineBetween(
                        point1: previousPoint,
                        point2: lastPoint,
                        color: .systemGreen,
                        thickness: 0.004
                    )
                    // 添加尺寸显示面板
                    addLabelNode(to: lineNode, startPoint: previousPoint, endPoint: lastPoint)
                    allLineNodes.append(lineNode)
                    sceneView.scene.rootNode.addChildNode(lineNode)
                }
                
            case .polygon:
                let lastPoint = allSidePoints[allSidePoints.count - 1]
                let previousPoint = allSidePoints[allSidePoints.count - 2]
                
                clearDashedLine()
                
                let lineNode = createLineBetween(
                    point1: previousPoint,
                    point2: lastPoint,
                    color: .systemGreen,
                    thickness: 0.004
                )
                // 添加尺寸显示面板
                addLabelNode(to: lineNode, startPoint: previousPoint, endPoint: lastPoint)
                allLineNodes.append(lineNode)
                sceneView.scene.rootNode.addChildNode(lineNode)
            }
        }
    }
    
    private func addLabelNode(to lineNode: SCNNode, startPoint: SCNVector3, endPoint: SCNVector3) {
        if let currentLabelNode = dashLineManager.currentLabelNode {
            let middlePosition = dashLineManager.midPointBetween(startPoint, endPoint)
            currentLabelNode.position = SCNVector3(x: middlePosition.x, y: middlePosition.y + 0.0025, z: middlePosition.z)
            lineNode.addChildNode(currentLabelNode)
//            currentLabelNode.look(at: startPoint, up: sceneView.scene.rootNode.worldFront, localFront: SCNVector3(0, 1, 0))

            dashLineManager.currentLabelNode = nil
        }
    }
    
    // MARK: - 清楚旧的虚线
    private func clearDashedLine() {
        dashedLineNode?.removeFromParentNode()
        previousDashedLineNode?.removeFromParentNode()
        dashedLineNode = nil
        previousDashedLineNode = nil
    }
    
    
    private func checkSnapToLineEndpoints(centerPosition:SCNVector3, lineEndpoints: [SCNVector3]) {
        let focusPosition = centerPosition
        
        // 吸附范围
        let snapRange: Float = 0.05// 5cm
        
        // 如果已经吸附了 那就只针对当前吸附的点去计算是不是大于 5cm
        if isAdsorption {
            if let endPoint = adsorptionPoint {
                let distance = focusPosition.distance(to: endPoint)
                if distance <= snapRange {
                    // 小于 5cm 自动吸附
                    snapToEndpoint(focusSquare: focusSquare, endpoint: endPoint)
//                    currentAdsorptionLocation = endPoint
                    return
                } else {
                    // 大于 5cm 回到初始位置
                    resetFocusSquareCenter(focusSquare: focusSquare)
//                    currentAdsorptionLocation = nil
                }
            }
        } else {
            for endPoint in lineEndpoints {
                let distance = focusPosition.distance(to: endPoint)
                if distance <= snapRange {
                    // 小于 5cm 自动吸附
                    snapToEndpoint(focusSquare: focusSquare, endpoint: endPoint)
//                    currentAdsorptionLocation = endPoint
                    
                    return
                } else {
                    // 大于 5cm 回到初始位置
                    resetFocusSquareCenter(focusSquare: focusSquare)
//                    currentAdsorptionLocation = nil
                }
            }
        }
        
        
    }
    
    private func snapToEndpoint(focusSquare: FocusSquare, endpoint: SCNVector3) {
        focusSquare.centerNode.worldPosition = endpoint

        if !isAdsorption {
            adsorptionPoint = endpoint
            // 吸附到端点
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            isAdsorption = true
            // 如果是绘制多边形，吸附到断点会默认把虚线绘制过去
            
            if isDrawing {
                if drawMode == .line {
                    // 绘制线过程中吸附到的点的位置，如果结束绘制，那么终点就是吸附点，并且不需要创建 endSphere，只需要画直线
                    endAdsorptionLocation = endpoint
                }
                if let dashedLineNode = self.dashedLineNode, let startLocation = startLocation {
                    self.dashLineManager.updateDashedLine(
                        node: dashedLineNode,
                        start: startLocation,
                        end: endpoint,
                        color: .white,
                        thickness: 0.005,
                        segmentLength: 0.01,
                        spaceLength: 0.005
                    )
                    self.endLocation = endpoint
                }
            }
        }
    }
    
    private func resetFocusSquareCenter(focusSquare: FocusSquare) {
        let initialPosition = SIMD3<Float>(0, 0.005, 0)
        focusSquare.centerNode.simdPosition = initialPosition
        if isAdsorption {
            // 直接设置位置为初始位置
            isAdsorption = false
            adsorptionPoint = nil
            endAdsorptionLocation = nil
        }
    }
    
    // MARK: - 创建实线
    private func createLineBetween(point1: SCNVector3, point2: SCNVector3, color: UIColor, thickness: CGFloat) -> SCNNode {
        let vector = point2 - point1
        let distance = vector.length()
        
        let cylinder = SCNCylinder(radius: thickness / 2, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = color
        
        let cylinderNode = SCNNode(geometry: cylinder)
        cylinderNode.position = (point1 + point2) / 2
        cylinderNode.look(at: point2, up: sceneView.scene.rootNode.worldUp, localFront: SCNVector3(0, 1, 0))
        
        let lineNode = SCNNode()
        lineNode.addChildNode(cylinderNode)
        
        // 创建起点和终点球体
        let sphere1 = SCNSphere(radius: thickness * 1.5)
        sphere1.firstMaterial?.diffuse.contents = UIColor.white // 起点颜色
        let sphereNode1 = SCNNode(geometry: sphere1)
        sphereNode1.position = point1
        lineNode.addChildNode(sphereNode1)

        
        switch drawMode {
        case .line:
            if endAdsorptionLocation == nil {
                let sphere2 = SCNSphere(radius: thickness * 1.5)
                sphere2.firstMaterial?.diffuse.contents = UIColor.white // 终点颜色
                let sphereNode2 = SCNNode(geometry: sphere2)
                sphereNode2.position = point2
                lineNode.addChildNode(sphereNode2)
            }
        case .polygon:
            if !isAdsorption {
                let sphere2 = SCNSphere(radius: thickness * 1.5)
                sphere2.firstMaterial?.diffuse.contents = UIColor.white // 终点颜色
                let sphereNode2 = SCNNode(geometry: sphere2)
                sphereNode2.position = point2
                lineNode.addChildNode(sphereNode2)
            }
        }
        
        return lineNode
    }
}

extension ARSceneController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.updateFocusSquare(isObjectVisible: false)
            if !self.lineEndPoints.isEmpty {
                let screenCenter = self.sceneView.screenCenter
                guard let hitTestResult = self.sceneView.smartHitTest(screenCenter) else { return }
                // 超过两个点（也就是有一条线了）才允许检查吸附
                if self.allSidePoints.count >= 2 {
                    self.checkSnapToLineEndpoints(centerPosition: SCNVector3(hitTestResult.worldTransform.translation), lineEndpoints: self.lineEndPoints)
                }
            }
        }
        
        DispatchQueue.main.async {
            let screenCenter = self.sceneView.screenCenter
            guard let hitTestResult = self.sceneView.smartHitTest(screenCenter), self.dashedLineNode != nil else { return }
            let endLocation = SCNVector3(hitTestResult.worldTransform.translation)
            // 如果已经吸附了就不让他主动更新
            if !self.isAdsorption {
//                self.updateDashedLine(to: endLocation)
                if let dashedLineNode = self.dashedLineNode, let startLocation = self.startLocation {
                    self.endLocation = endLocation
                    self.dashLineManager.updateDashedLine(
                        node: dashedLineNode,
                        start: startLocation,
                        end: endLocation,
                        color: .white,
                        thickness: 0.005,
                        segmentLength: 0.01,
                        spaceLength: 0.005
                    )
                }
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



//import UIKit
//import ARKit
//
//class ARSceneController: UIViewController, ARSCNViewDelegate {
//    private lazy var sceneView: ARSCNView = {
//        let view = ARSCNView()
//        view.delegate = self
//        view.automaticallyUpdatesLighting = true
//        return view
//    }()
//
//    private let lineManager = LineManager() // 集成 LineManager
//    private var dashedLineNode: SCNNode?
//    private var isDrawing = false
//    private var startPoint: SCNVector3?
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        setupSceneView()
//        setupGestures()
//    }
//
//    private func setupSceneView() {
//        sceneView.frame = view.bounds
//        view.addSubview(sceneView)
//    }
//    
//    public override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//        resetTracking()
//    }
//    
//    public override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//        sceneView.session.pause()
//    }
//    
//    private func resetTracking() {
//        let configuration = ARWorldTrackingConfiguration()
//        configuration.planeDetection = [.horizontal, .vertical]
//        configuration.isLightEstimationEnabled = true
//        configuration.environmentTexturing = .automatic
//        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
//    }
//    
//
//    private func setupGestures() {
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
//        sceneView.addGestureRecognizer(tapGesture)
//    }
//
//    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
//        let tapLocation = gesture.location(in: sceneView)
//        guard let hitResult = sceneView.hitTest(tapLocation, types: .featurePoint).first else { return }
//        let hitPosition = SCNVector3(
//            hitResult.worldTransform.columns.3.x,
//            hitResult.worldTransform.columns.3.y,
//            hitResult.worldTransform.columns.3.z
//        )
//
//        if isDrawing {
//            finishDrawing(to: hitPosition)
//        } else {
//            startDrawing(from: hitPosition)
//        }
//    }
//
//    private func startDrawing(from startPoint: SCNVector3) {
//        self.startPoint = startPoint
//        dashedLineNode = SCNNode()
//        sceneView.scene.rootNode.addChildNode(dashedLineNode!)
//        isDrawing = true
//    }
//
//    private func finishDrawing(to endPoint: SCNVector3) {
//        guard let startPoint = startPoint else { return }
//        let lineNode = lineManager.createLineBetween(
//            start: startPoint,
//            end: endPoint,
//            color: .blue,
//            thickness: 0.01
//        )
//        sceneView.scene.rootNode.addChildNode(lineNode)
//
//        dashedLineNode?.removeFromParentNode()
//        dashedLineNode = nil
//        isDrawing = false
//    }
//
//    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
//        guard let startPoint = startPoint, isDrawing else { return }
//        DispatchQueue.main.async {
//            let screenCenter = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
//            guard let hitResult = self.sceneView.hitTest(screenCenter, types: .featurePoint).first else { return }
//            let endPoint = SCNVector3(
//                hitResult.worldTransform.columns.3.x,
//                hitResult.worldTransform.columns.3.y,
//                hitResult.worldTransform.columns.3.z
//            )
//
//            if let dashedLineNode = self.dashedLineNode {
//                self.lineManager.updateDashedLine(
//                    node: dashedLineNode,
//                    start: startPoint,
//                    end: endPoint,
//                    color: .green,
//                    thickness: 0.005,
//                    segmentLength: 0.02,
//                    spaceLength: 0.01
//                )
//            }
//        }
//    }
//}

