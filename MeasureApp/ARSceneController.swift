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
    private var dashedLineNodes: [SCNNode] = [] // 当前绘制的虚线点
    private var previousDashedLineNodes: [SCNNode] = [] // 前一个绘制的虚线点
    
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
    
    private var finishedDashedLines: [[SCNNode]] = [] // 已完成的虚线集合
    private var lineEndPoints: [SCNVector3] = []
    
    private var drawMode: DrawMode = .line
    
    
    // 是否已经吸附了，防止震动反馈多次
    private var isAdsorption: Bool = false
    private var adsorptionPoint: SCNVector3? //当前动态判断的吸附点坐标 超过距离就为 nil
    private var startAdsorptionLocation: SCNVector3? // 从吸附点绘制的起点
    private var endAdsorptionLocation: SCNVector3? // 绘制过程中吸附到的点的位置，如果结束绘制，那么终点就是吸附点，并且不需要创建 endSphere，只需要画直线
    private var allLineNodes: [SCNNode] = []
    private var currentLabelNode: SCNNode?
    
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
        var initialEndLocation = startLocation

        // 如果是吸附状态的话 用最后一个点当做起点
        if isAdsorption {
            if let lastPosition = adsorptionPoint {
                startLocation = lastPosition
                initialEndLocation = startLocation
                startAdsorptionLocation = lastPosition
            }
        }
        
        // 所有节点位置的集合
        allSidePoints.append(startLocation)
        dashedLineNodes = createDashedLine(from: startLocation, to: initialEndLocation, interval: 0.01, radius: 0.002, color: .white)
        
        for node in dashedLineNodes {
            sceneView.scene.rootNode.addChildNode(node)
        }
        
        if drawMode == .polygon {
            if allSidePoints.count >= 2 {
                let lastPoint = allSidePoints[allSidePoints.count - 1]
                let previousPoint = allSidePoints[allSidePoints.count - 2]
                
                for node in previousDashedLineNodes {
                    node.removeFromParentNode()
                }
                previousDashedLineNodes.removeAll()
                
                let lineNode = createLineBetween(
                    point1: previousPoint,
                    point2: lastPoint,
                    color: .systemGreen,
                    thickness: 0.004 // 默认的线宽
                )
                allLineNodes.append(lineNode)
                sceneView.scene.rootNode.addChildNode(lineNode)
            }
        }
    }

    // 结束绘制虚线
    private func finishDrawing() {
        isDrawing = false
        // 将当前虚线保存到已完成虚线集合
        finishedDashedLines.append(dashedLineNodes)
        
        // 结束点
        if let lastNode = dashedLineNodes.last {
            lineEndPoints.append(lastNode.position)
            // 把所有的点加进 allSidePoints 里进行筛选操作
            allSidePoints.append(lastNode.position)
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
                allLineNodes.append(lineNode)
                sceneView.scene.rootNode.addChildNode(lineNode)
            }
        }
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
        guard var startLocation = startLocation else { return }
        
        // 计算起始点至当前点的距离
        let currentDistance = endLocation.distance(to: startLocation)
        let middlePosition = SCNVector3(
            (startLocation.x + endLocation.x) / 2,
            (startLocation.y + endLocation.y) / 2,
            (startLocation.z + endLocation.z) / 2
        )
        
        // 计算直线方向向量（在 xz 平面内）
        let directionVector = SCNVector3(
            endLocation.x - startLocation.x,
            0, // y 保持为 0，表示在 xz 平面
            endLocation.z - startLocation.z
        )

        // 归一化方向向量
        let directionLength = sqrt(directionVector.x * directionVector.x + directionVector.z * directionVector.z)
        let normalizedDirection = SCNVector3(directionVector.x / directionLength, 0, directionVector.z / directionLength)

        // 计算旋转角度（绕 y 轴旋转）
        let angle = atan2(normalizedDirection.z, normalizedDirection.x)

        // 创建旋转矩阵
        let rotation = SCNMatrix4MakeRotation(-angle, 0, 1, 0) // 绕 y 轴旋转
        
        
        if currentDistance >= 0.1 {// 大于文字面板的宽度
            let roundedDistance = Int(currentDistance * 100)
            if let currentLabelNode = currentLabelNode {
                updateLabelNode(text: "\(roundedDistance) cm")
                // 注意这里需要先应用旋转再设置位置，不然会让 position 的 y 变成 0
                currentLabelNode.transform = rotation
                currentLabelNode.position = middlePosition

            } else {
                let labelNode = createLabelNode(text: "\(roundedDistance) cm", width: 0.1, height: 0.05)
                // 注意这里需要先应用旋转再设置位置，不然会让 position 的 y 变成 0
                labelNode.transform = rotation
                labelNode.position = middlePosition
                sceneView.scene.rootNode.addChildNode(labelNode)
                currentLabelNode = labelNode
            }
        }
        
        // 如果是从吸附点开始绘制的 那么更新的时候虚线起点也是吸附点
        if let startAdsorptionLocation = startAdsorptionLocation {
            startLocation = startAdsorptionLocation
        }
        
        // 1. 先清除旧虚线
        clearDashedLine()

        // 2. 创建新的虚线
        dashedLineNodes = createDashedLine(from: startLocation, to: endLocation, interval: 0.01, radius: 0.002, color: .white)
        for node in dashedLineNodes {
            sceneView.scene.rootNode.addChildNode(node)
        }
        previousDashedLineNodes = dashedLineNodes
    }
    
    // MARK: - 清楚旧的虚线
    private func clearDashedLine() {
        for node in dashedLineNodes {
            node.removeFromParentNode()
        }
        dashedLineNodes.removeAll()
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
                updateDashedLine(to: endpoint)
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
        // 计算两点之间的向量
        let vector = point2 - point1
        let distance = vector.length()
        
        // 创建圆柱体表示直线
        let cylinder = SCNCylinder(radius: thickness / 2, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = color
        
        // 创建圆柱体节点
        let cylinderNode = SCNNode(geometry: cylinder)
        
        // 设置圆柱体的中心位置
        cylinderNode.position = (point1 + point2) / 2
        
        // 计算圆柱体的朝向
        cylinderNode.look(at: point2, up: sceneView.scene.rootNode.worldUp, localFront: SCNVector3(0, 1, 0))
        
        // 创建线段的父节点
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
    
    // 创建尺寸显示面板
    private func createLabelNode(text: String, width: CGFloat, height: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        
        // 这边 * 1000 是为了提高分辨率
        let size = CGSize(width: width * 1000, height: height * 1000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.fillPath()
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let fontSize = size.height * 0.4
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,  // 水平居中
                y: (size.height - textSize.height) / 2, // 垂直居中
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.isDoubleSided = true
        
        let planeNode = SCNNode(geometry: plane)
        
//        let constraint = SCNBillboardConstraint()
//        constraint.freeAxes = [.Y]
//        planeNode.constraints = [constraint]
        
        return planeNode
    }
    
    private func updateLabelNode(text: String, alpha: CGFloat = 0.8) {
        if let existingLabelNode = currentLabelNode,
           let plane = existingLabelNode.geometry as? SCNPlane {
            let width = plane.width
            let height = plane.height
            // 这边 * 1000 是为了提高分辨率
            let size = CGSize(width: width * 1000, height: height * 1000)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                
                let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
                ctx.cgContext.addPath(path.cgPath)
                ctx.cgContext.fillPath()
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                
                let fontSize = size.height * 0.4
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraphStyle
                ]
                
                let textSize = text.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (size.width - textSize.width) / 2,  // 水平居中
                    y: (size.height - textSize.height) / 2, // 垂直居中
                    width: textSize.width,
                    height: textSize.height
                )
                
                text.draw(in: textRect, withAttributes: attributes)
            }
            plane.firstMaterial?.diffuse.contents = image
            plane.firstMaterial?.isDoubleSided = true
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
                // 超过两个点（也就是有一条线了）才允许检查吸附
                if self.allSidePoints.count >= 2 {
                    self.checkSnapToLineEndpoints(centerPosition: SCNVector3(hitTestResult.worldTransform.translation), lineEndpoints: self.lineEndPoints)
                }
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

