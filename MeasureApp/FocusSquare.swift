//
//  FocusSquare.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/17.
//


import Foundation
import ARKit

class FocusSquare: SCNNode {
    // MARK: - Types
    
    enum State: Equatable {
        case initializing
        case detecting(raycastResult: ARRaycastResult, camera: ARCamera?)
    }
    
    /// 根据当前状态获取聚焦框最近的位置
    var lastPosition: SIMD3<Float>? {
        switch state {
        case .initializing: return nil
        case .detecting(let raycastResult, _): return raycastResult.worldTransform.translation
        }
    }
    
    var state: State = .initializing {
        didSet {
            guard state != oldValue else { return }
            
            switch state {
            case .initializing:
                displayAsBillboard()
                
            case let .detecting(raycastResult, camera):
                if let planeAnchor = raycastResult.anchor as? ARPlaneAnchor {
                    displayWithPlaneAnchor(for: raycastResult, planeAnchor: planeAnchor, camera: camera)
                } else {
                    displayWithoutPlaneAnchor(for: raycastResult, camera: camera)
                }
            }
        }
    }
    
    /// 聚焦框的初始大小（以米为单位）
    static let size: Float = 0.20
    
    /// 动画持续时间
    static let animationDuration = 0.2
    
    /// 是否正在动画
    private var isAnimating = false
    
    /// 当前是否正在改变方向（当摄像头朝下时）
    private var isChangingOrientation = false
    
    /// 摄像头是否正指向地面
    private var isPointingDownwards = true
    
    /// 聚焦框最近的位置列表
    private var recentFocusSquarePositions: [SIMD3<Float>] = []
    
    /// 之前已到过的的平面锚点集合
    private var anchorsOfVisitedPlanes: Set<ARAnchor> = []
        
    /// 控制其他 `FocusSquare` node 的 main node
    private var positioningNode = SCNNode()
    
    /// 用于管理方向更新的计数器
    private var counterToNextOrientationUpdate: Int = 0
    
    public var centerNode = SCNNode()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        opacity = 0.0
        
        let plane = SCNPlane(width: 1, height: 1)
        plane.firstMaterial?.diffuse.contents = UIImage(named: "focus_square")//UIColor.red
        plane.firstMaterial?.lightingModel = .constant
        positioningNode = SCNNode(geometry: plane)
        positioningNode.simdEulerAngles = simd_float3(-.pi / 2.0, 0, 0)
        positioningNode.simdPosition = simd_float3(0, 0, 0)
        
        // 始终将聚焦框渲染在其他内容之上
        displayNodeHierarchyOnTop(true)
        
        let sphere = SCNSphere(radius: 0.008)
        sphere.firstMaterial?.diffuse.contents = UIColor.white
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.simdPosition = simd_float3(0, 0.005, 0)// 这个地方给个 y 值是因为要让指引框的中心球的位置在虚线球的上方，让虚线球是从中心球下方出来，而不是从中心球内部出来
        sphereNode.renderingOrder = 1000;
        centerNode = sphereNode
        
        addChildNode(sphereNode)
        addChildNode(positioningNode)
        
        // 初始状态显示为方形样式
        displayAsBillboard()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) has not been implemented")
    }
    
    // MARK: - Appearance
    
    /// 隐藏聚焦框
    func hide() {
        guard action(forKey: "hide") == nil else { return }
        
        displayNodeHierarchyOnTop(false)
        runAction(.fadeOut(duration: 0.5), forKey: "hide")
    }
    
    /// 显示聚焦框
    func unhide() {
        guard action(forKey: "unhide") == nil else { return }
        
        displayNodeHierarchyOnTop(true)
        runAction(.fadeIn(duration: 0.5), forKey: "unhide")
    }
    
    /// 将聚焦框显示为与摄像机平面平行的方形样式
    private func displayAsBillboard() {
        simdTransform = matrix_identity_float4x4
        eulerAngles.x = .pi / 2
        simdPosition = [0, 0, -0.8]
        unhide()
        performWorkingAnimation()
    }

    /// 当没有检测到平面时调用
    private func displayWithoutPlaneAnchor(for raycastResult: ARRaycastResult, camera: ARCamera?) {
        performWorkingAnimation()
        setPosition(with: raycastResult, camera)
    }
        
    /// 当检测到一个平面时调用
    private func displayWithPlaneAnchor(for raycastResult: ARRaycastResult, planeAnchor: ARPlaneAnchor, camera: ARCamera?) {
        performStandByAnimation(flash: !anchorsOfVisitedPlanes.contains(planeAnchor))
        anchorsOfVisitedPlanes.insert(planeAnchor)
        setPosition(with: raycastResult, camera)
    }
    
    // - Tag: 设置空间3DPosition
    func setPosition(with raycastResult: ARRaycastResult, _ camera: ARCamera?) {
        let position = raycastResult.worldTransform.translation
        recentFocusSquarePositions.append(position)
        updateTransform(for: raycastResult, camera: camera)
    }

    // MARK: Helper Methods
    
    // - Tag: 设置3DOrientation
    func updateOrientation(basedOn raycastResult: ARRaycastResult) {
        self.simdOrientation = raycastResult.worldTransform.orientation
    }
    
    /// 更新聚焦框的变换以与摄像头对齐
    private func updateTransform(for raycastResult: ARRaycastResult, camera: ARCamera?) {
        // 使用最近的多个位置求平均值 为了速度快点 就先设置 3 吧
        recentFocusSquarePositions = Array(recentFocusSquarePositions.suffix(3))
        
        // 移动到最近位置的平均值以减少抖动
        let average = recentFocusSquarePositions.reduce([0, 0, 0], { $0 + $1 }) / Float(recentFocusSquarePositions.count)
        self.simdPosition = average
        self.simdScale = [1.0, 1.0, 1.0] * scaleBasedOnDistance(camera: camera)
        
        // 当摄像头接近水平时修正 Y 轴旋转以避免万向节锁导致的抖动
        guard let camera = camera else { return }
        let tilt = abs(camera.eulerAngles.x)
        let threshold: Float = .pi / 2 * 0.75
        
        if tilt > threshold {
            if !isChangingOrientation {
                let yaw = atan2f(camera.transform.columns.0.x, camera.transform.columns.1.x)
                
                isChangingOrientation = true
                SCNTransaction.begin()
                SCNTransaction.completionBlock = {
                    self.isChangingOrientation = false
                    self.isPointingDownwards = true
                }
                SCNTransaction.animationDuration = isPointingDownwards ? 0.0 : 0.5
                self.simdOrientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                SCNTransaction.commit()
            }
        } else {
            // 为了减少抖动，每秒仅更新两次方向
            if counterToNextOrientationUpdate == 30 || isPointingDownwards {
                counterToNextOrientationUpdate = 0
                isPointingDownwards = false
                
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                updateOrientation(basedOn: raycastResult)
                SCNTransaction.commit()
            }
            
            counterToNextOrientationUpdate += 1
        }
    }

    /**
     通过根据距离缩放来减少视觉尺寸的变化。
     
     对于距离小于 0.7 米的情况，缩放比例为 1.0x（例如，桌子上的物体），
     对于距离 1.5 米的情况，缩放比例为 1.2x（例如，地板上的物体）。
     */
    private func scaleBasedOnDistance(camera: ARCamera?) -> Float {
        guard let camera = camera else { return 1.0 }

        let distanceFromCamera = simd_length(simdWorldPosition - camera.transform.translation)
        if distanceFromCamera < 0.7 {
            return distanceFromCamera / 0.7
        } else {
            return 0.25 * distanceFromCamera + 0.825
        }
    }
    
    // MARK: Animations
    
    private func performWorkingAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        
        // 添加缩放/弹簧动画
        SCNTransaction.begin()
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        SCNTransaction.animationDuration = FocusSquare.animationDuration / 4
        positioningNode.simdScale = [1.0, 1.0, 1.0] * FocusSquare.size
        SCNTransaction.commit()
    }

    private func performStandByAnimation(flash: Bool = false) {
        guard !isAnimating else { return }
        isAnimating = true
        positioningNode.opacity = 1.0
        
        if flash {
            let waitAction = SCNAction.wait(duration: FocusSquare.animationDuration * 0.75)
            let flashSquareAction = flashAnimation(duration: FocusSquare.animationDuration * 0.25)
            positioningNode.runAction(.sequence([waitAction, flashSquareAction]))
         }
    }
    
    // MARK: Convenience Methods
    
    /// 设置 `positioningNode` 的渲染顺序以显示在其他场景内容之上或之下
    func displayNodeHierarchyOnTop(_ isOnTop: Bool) {
        // 递归遍历节点的子节点，根据 `isOnTop` 参数更新渲染顺序
        func updateRenderOrder(for node: SCNNode) {
            node.renderingOrder = isOnTop ? 2 : 0
            
            for material in node.geometry?.materials ?? [] {
                material.readsFromDepthBuffer = !isOnTop
            }
            
            for child in node.childNodes {
                updateRenderOrder(for: child)
            }
        }
        
        updateRenderOrder(for: positioningNode)
    }
}

// MARK: - Animations and Actions
private func flashAnimation(duration: TimeInterval) -> SCNAction {
    let action = SCNAction.customAction(duration: duration) { (node, elapsedTime) -> Void in
        // 将颜色从 HSB 48/100/100 动画过渡到 48/30/100 再回到 48/100/100
        let elapsedTimePercentage = elapsedTime / CGFloat(duration)
        let saturation = 2.8 * (elapsedTimePercentage - 0.5) * (elapsedTimePercentage - 0.5) + 0.3
        if let material = node.geometry?.firstMaterial {
            material.diffuse.contents = UIColor(hue: 0.1333, saturation: saturation, brightness: 1.0, alpha: 1.0)
        }
    }
    return action
}

