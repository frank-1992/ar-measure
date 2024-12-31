//
//  LineManager.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/31.
//

import SceneKit


class DashLineManager {
    
    private var currentLabelNode: SCNNode?
    
    // MARK: - 创建虚线（球体）
    func createDashedLine(start: SCNVector3, end: SCNVector3, color: UIColor, thickness: CGFloat, segmentLength: CGFloat, spaceLength: CGFloat) -> SCNNode {
        let totalDistance = distanceBetween(start, end)
        let direction = normalize(vector: end - start)
        
        let positions = stride(from: 0.0, to: totalDistance, by: Double(segmentLength + spaceLength)).map {
            start + direction * Float($0)
        }
        
        // 使用 SCNGeometry 批量渲染球体
        let sphere = SCNSphere(radius: thickness / 2)
        sphere.firstMaterial?.diffuse.contents = color
        
        let geometrySources = positions.map { position -> SCNNode in
            let node = SCNNode(geometry: sphere.copy() as? SCNGeometry)
            node.position = position
            return node
        }
        
        let parentNode = SCNNode()
        geometrySources.forEach { parentNode.addChildNode($0) }
        
        return parentNode
    }
    
    // MARK: - 更新虚线
    func updateDashedLine(node: SCNNode, start: SCNVector3, end: SCNVector3, color: UIColor, thickness: CGFloat, segmentLength: CGFloat, spaceLength: CGFloat) {
        DispatchQueue.global(qos: .userInitiated).async {
            let newLine = self.createDashedLine(start: start, end: end, color: color, thickness: thickness, segmentLength: segmentLength, spaceLength: spaceLength)
            DispatchQueue.main.async {
                node.childNodes.forEach { $0.removeFromParentNode() }
                node.addChildNode(newLine)
                
                // 添加或更新尺寸面板
                let roundedDistance = Int(self.distanceBetween(start, end) * 100)
                if let _ = node.childNode(withName: "SizePanel", recursively: false) {
                    self.updateLabelNode(text: "\(roundedDistance) cm")
                } else {
                    let sizePanel = self.createLabelNode(text: "\(roundedDistance) cm", width: 0.1, height: 0.05)
                    sizePanel.name = "SizePanel"
                    
                    // 计算虚线方向的旋转
                    let direction = self.normalize(vector: end - start)
                    let angleXZ = atan2(direction.z, direction.x)
                    var rotationMatrix = SCNMatrix4MakeRotation(-angleXZ, 0, 1, 0)

                    // 让面板围绕直线方向轴旋转 -90°，实现平躺在直线上
                    let axisRotation = SCNMatrix4MakeRotation(-.pi / 2, direction.x, direction.y, direction.z)
                    rotationMatrix = SCNMatrix4Mult(rotationMatrix, axisRotation)
                    sizePanel.transform = rotationMatrix
                    
                    let middlePosition = self.midPointBetween(start, end)
                    sizePanel.position = SCNVector3(x: middlePosition.x, y: middlePosition.y + 0.0025, z: middlePosition.z)

                    self.currentLabelNode = sizePanel
                    node.addChildNode(sizePanel)
                }
            }
        }
    }
    
    
    // MARK: - 创建尺寸显示面板
    private func createLabelNode(text: String, width: CGFloat, height: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        
        // 这边 * 1000 是为了提高分辨率
        let size = CGSize(width: width * 1000, height: height * 1000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(1.0).cgColor)
            
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
        planeNode.renderingOrder = 1000
        
        return planeNode
    }
    
    // MARK: - 更新尺寸显示面板
    private func updateLabelNode(text: String, alpha: CGFloat = 1.0) {
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
    
    
    // MARK: - 工具方法
    private func distanceBetween(_ start: SCNVector3, _ end: SCNVector3) -> CGFloat {
        return CGFloat(sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2) + pow(end.z - start.z, 2)))
    }
    
    private func midPointBetween(_ start: SCNVector3, _ end: SCNVector3) -> SCNVector3 {
        return SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
    }
    
    private func normalize(vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }
}
