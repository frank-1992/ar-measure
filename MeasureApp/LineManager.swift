//
//  LineManager.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/31.
//

import SceneKit
import ARKit

public struct LineConstants {
    // 单位 m
    // 虚线段（球体）的直径
    static let dashLineThickness: CGFloat = 0.004
    // 下面两个值控制密度
    static let segmentLength: CGFloat = 0.005
    static let spaceLength: CGFloat = 0.005
    static let lineThickness: CGFloat = 0.003
}

public struct SizePanel {
    static let name: String = "SizePanel"
    static let width: CGFloat = 0.08
    static let height: CGFloat = 0.04
    static let sizeFix: Float = 0.05
    static let alpha: CGFloat = 0.8
}

class DashLineManager {
    public var currentSizePanel: SizePanelNode?
    
    // 预先创建的小球节点数组
    private var sphereNodes: [SCNNode] = []

    public var rootNode: SCNNode?
    public var cameraNode: SCNNode?
    
    // MARK: - 更新虚线
    public func updateDashedLine(node: SCNNode, start: SCNVector3, end: SCNVector3, color: UIColor, thickness: CGFloat, segmentLength: CGFloat, spaceLength: CGFloat) {
        DispatchQueue.global(qos: .userInitiated).async {
            let positions = self.calculatePositions(start: start, end: end, segmentLength: segmentLength, spaceLength: spaceLength)
            
            DispatchQueue.main.async {
                // 调整小球节点的数量（超过就在当前集合里增加）
                self.adjustSphereNodes(count: positions.count, color: color, thickness: thickness)
                
                // 更新小球节点的位置
                for (index, position) in positions.enumerated() {
                    let sphereNode = self.sphereNodes[index]
                    sphereNode.position = position
                    if index == 0 {
                        sphereNode.scale = SCNVector3(1, 1, 1) * 2.5
                    }
                    sphereNode.isHidden = false
                }
                
                // 隐藏多余的小球节点
                for index in positions.count..<self.sphereNodes.count {
                    self.sphereNodes[index].isHidden = true
                }
                
                for sphereNode in self.sphereNodes {
                    if sphereNode.parent == nil {
                        node.addChildNode(sphereNode)
                    }
                }
                
                let lineDirection = (start - end).normalized()
                let middlePosition = self.midPointBetween(start, end)
                let distance = self.distanceBetween(start, end)
                let roundedDistance = Int(distance * 100)
                
                let cameraPosition = self.cameraNode?.position ?? SCNVector3Zero
                
                let angle = atan2(lineDirection.z, lineDirection.x) * 180 / .pi
                let shouldFlip = (angle < 90 && angle > -90)
                
                // 添加或更新尺寸面板
                if let currentSizePanel = self.currentSizePanel {
                    if distance >= SizePanel.width {
                        currentSizePanel.isHidden = false
                        self.adjustPanelNodeRotation(sizePanel: currentSizePanel, start: start, end: end, cameraPosition: cameraPosition)
                        currentSizePanel.position = SCNVector3(x: middlePosition.x,
                                                        y: middlePosition.y,
                                                        z: middlePosition.z)
                        currentSizePanel.updateText(text: "\(roundedDistance) cm", shouldRotate: shouldFlip)
                    } else {
                        currentSizePanel.isHidden = true
                    }
                } else {
                    if distance >= SizePanel.width {
                        let planeNode = SizePanelNode(width: SizePanel.width, height: SizePanel.height, text: "\(roundedDistance) cm")
                        self.adjustPanelNodeRotation(sizePanel: planeNode, start: start, end: end, cameraPosition: cameraPosition)
                        planeNode.position = SCNVector3(x: middlePosition.x,
                                                        y: middlePosition.y,
                                                        z: middlePosition.z)
                        self.currentSizePanel = planeNode
                        self.rootNode?.addChildNode(planeNode)
                    }
                }
            }
        }
    }
    
    // 计算小球的位置
    private func calculatePositions(start: SCNVector3, end: SCNVector3, segmentLength: CGFloat, spaceLength: CGFloat) -> [SCNVector3] {
        let totalDistance = distanceBetween(start, end)
        let direction = normalize(vector: end - start)
        return stride(from: 0.0, to: Double(totalDistance), by: Double(segmentLength + spaceLength)).map {
            start + direction * Float($0)
        }
    }
    
    // 调整小球节点的数量
    private func adjustSphereNodes(count: Int, color: UIColor, thickness: CGFloat) {
        // 检测 sphereNodes 数组中的 sphereNode 是否已经从场景中移除
        sphereNodes = sphereNodes.filter { sphereNode in
            return sphereNode.parent != nil && sphereNode.parent?.parent != nil
        }
        
        while sphereNodes.count < count {
            let sphere = SCNSphere(radius: thickness / 2)
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.transparency = 0.8
            sphere.firstMaterial = material
            let node = SCNNode(geometry: sphere)
            sphereNodes.append(node)
        }
    }
    
    
    public func adjustPanelNodeRotation(sizePanel: SCNNode, start: SCNVector3, end: SCNVector3, cameraPosition: SCNVector3) {
        let lineDirection = (end - start).normalized()
        let panelNormal = lineDirection.cross(cameraPosition - start).normalized()
        let panelUp = panelNormal.cross(lineDirection).normalized()
        
        var transform = sizePanel.transform
        transform.m11 = lineDirection.x
        transform.m12 = lineDirection.y
        transform.m13 = lineDirection.z
        transform.m21 = panelUp.x
        transform.m22 = panelUp.y
        transform.m23 = panelUp.z
        transform.m31 = panelNormal.x
        transform.m32 = panelNormal.y
        transform.m33 = panelNormal.z
        
        sizePanel.transform = transform
    }
    
    public func setSizePanelTransparency(_ transparency: CGFloat) {
        guard let currentSizePanel = currentSizePanel else { return }
        currentSizePanel.updateTransparency(alpha: transparency)
    }
    
    
    private func distanceBetween(_ start: SCNVector3, _ end: SCNVector3) -> CGFloat {
        return CGFloat(sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2) + pow(end.z - start.z, 2)))
    }
    
    public func midPointBetween(_ start: SCNVector3, _ end: SCNVector3) -> SCNVector3 {
        return SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
    }
    
    private func normalize(vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }
}
