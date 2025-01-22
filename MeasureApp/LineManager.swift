import SceneKit
import ARKit


public struct LineConstants {
    // 单位 m
    // 虚线段（球体）的直径
    static let dashLineThickness: CGFloat = 0.003
    // 下面两个值控制密度
    static let segmentLength: CGFloat = 0.01
    static let spaceLength: CGFloat = 0.005
    static let lineThickness: CGFloat = 0.003
}

private struct SizePanel {
    static let name: String = "SizePanel"
    static let width: CGFloat = 0.08
    static let height: CGFloat = 0.04
    static let sizeFix: Float = 0.05
    static let alpha: CGFloat = 0.8
}

class DashLineManager {
    public var currentSizePanel: SCNNode?
    
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
                
                let lineDirection = (end - start).normalized()
                let middlePosition = self.midPointBetween(start, end)
                let distance = self.distanceBetween(start, end)
                let roundedDistance = Int(distance * 100)
                
                let cameraPosition = self.cameraNode?.position ?? SCNVector3Zero

                let middleToCamera = (cameraPosition - middlePosition).normalized()
                let shouldRotate = middleToCamera.dot(lineDirection) < 0


                // 添加或更新尺寸面板
                if let currentSizePanel = self.currentSizePanel, let planeNode = currentSizePanel.childNode(withName: SizePanel.name, recursively: false), let plane = planeNode.geometry as? SCNPlane {
                    if distance >= plane.width {
                        currentSizePanel.isHidden = false
                        self.adjustPanelNodeRotation(sizePanel: currentSizePanel, start: start, end: end)
                        currentSizePanel.position = SCNVector3(x: middlePosition.x,
                                                        y: middlePosition.y + Float(LineConstants.dashLineThickness / 2.0),
                                                        z: middlePosition.z)
                        self.updateLabelNode(plane: plane, text: "\(roundedDistance) cm", rotated: shouldRotate)
                    } else {
                        currentSizePanel.isHidden = true
                    }
                } else {
                    if distance >= SizePanel.width {
                        let sizePanel = SCNNode()
                        sizePanel.eulerAngles = SCNVector3(0, 0, 0)
                        let planeNode = self.createLabelNode(text: "\(roundedDistance) cm", width: SizePanel.width, height: SizePanel.height)
                        planeNode.name = SizePanel.name
                        sizePanel.addChildNode(planeNode)
                        self.adjustPanelNodeRotation(sizePanel: sizePanel, start: start, end: end)
                        sizePanel.position = SCNVector3(x: middlePosition.x,
                                                        y: middlePosition.y + Float(LineConstants.dashLineThickness / 2.0),
                                                        z: middlePosition.z)
                        self.currentSizePanel = sizePanel
                        self.rootNode?.addChildNode(sizePanel)
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
            return sphereNode.parent != nil
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
    
    private func adjustPanelNodeRotation(sizePanel: SCNNode, start: SCNVector3, end: SCNVector3) {
        let middlePosition = midPointBetween(start, end)
        let lineDirection = (end - start).normalized()
        let lookAtTarget = middlePosition + lineDirection
        sizePanel.look(at: lookAtTarget, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    }
    
    // MARK: - 创建尺寸显示面板
    private func createLabelNode(text: String, width: CGFloat, height: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        
        // 这边 * 2000 是为了提高分辨率
        let size = CGSize(width: width * 2000, height: height * 2000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(1.0).cgColor)
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.fillPath()
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let fontSize = size.height * 0.5
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
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
        plane.firstMaterial?.transparency = SizePanel.alpha
        
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.renderingOrder = 1000
        
        planeNode.eulerAngles.x = -.pi / 2
        planeNode.eulerAngles.y = -.pi / 2
        
        return planeNode
    }
    
    // MARK: - 更新尺寸显示面板
    private func updateLabelNode(plane: SCNPlane, text: String, alpha: CGFloat = 1.0, rotated: Bool = false) {
        let width = plane.width
        let height = plane.height
        
        // 这边 * 12000 是为了提高分辨率
        let size = CGSize(width: width * 2000, height: height * 2000)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.fillPath()
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let fontSize = size.height * 0.5
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            // 旋转上下文，使文字旋转 180 度（如果需要）
            if rotated {
                ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.cgContext.rotate(by: .pi) // 旋转 180 度
                ctx.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)
            }
            
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        plane.firstMaterial?.diffuse.contents = image
        plane.firstMaterial?.transparency = alpha
    }
    
    public func setSizePanelTransparency(_ transparency: CGFloat) {
        guard let plane = currentSizePanel?.geometry as? SCNPlane else {
            return
        }
        plane.firstMaterial?.transparency = transparency
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
