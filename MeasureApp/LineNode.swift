//
//  LineNode.swift
//  MeasureApp
//
//  Created by 吴熠 on 2025/1/22.
//

import SceneKit

class LineNode: SCNNode {
    var startPosition: SCNVector3
    var endPosition: SCNVector3
    
    init(start: SCNVector3, end: SCNVector3, color: UIColor, thickness: CGFloat) {
        self.startPosition = start
        self.endPosition = end
        super.init()
        
        let vector = end - start
        let distance = vector.length()
        
        let cylinder = SCNCylinder(radius: thickness / 2, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = color
        
        let cylinderNode = SCNNode(geometry: cylinder)
        cylinderNode.position = (start + end) / 2
        cylinderNode.look(at: end, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        self.addChildNode(cylinderNode)
        
        self.name = "3DLine"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SizePanelNode: SCNNode {
    
    private var planeNode: SCNNode?
    private var textImageSize: CGSize
    public var currentText: String = ""
    
    init(width: CGFloat, height: CGFloat, text: String) {
        textImageSize = CGSize(width: width * 1000, height: height * 1000)
        super.init()
        let plane = SCNPlane(width: width, height: height)
        
        let renderer = UIGraphicsImageRenderer(size: textImageSize)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: textImageSize)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: textImageSize.height / 2)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.fillPath()
        }
        
        plane.firstMaterial?.diffuse.contents = image
        
        plane.firstMaterial?.writesToDepthBuffer = false
        plane.firstMaterial?.readsFromDepthBuffer = false

        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.transparency = 1.0
        
        let planeNode = SCNNode(geometry: plane)
        addChildNode(planeNode)
        
        planeNode.renderingOrder = 1000
        planeNode.eulerAngles.x = -.pi / 2
        
        planeNode.name = SizePanel.name
        
        self.planeNode = planeNode
        
        updateText(text: text)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateText(text: String, shouldRotate: Bool = false) {
        currentText = text
        let renderer = UIGraphicsImageRenderer(size: textImageSize)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: textImageSize)
            ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(1.0).cgColor)
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: textImageSize.height / 2)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.fillPath()
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let fontSize = textImageSize.height * 0.5
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (textImageSize.width - textSize.width) / 2,  // 水平居中
                y: (textImageSize.height - textSize.height) / 2, // 垂直居中
                width: textSize.width,
                height: textSize.height
            )
            
            if shouldRotate {
                ctx.cgContext.translateBy(x: textImageSize.width / 2, y: textImageSize.height / 2)
                ctx.cgContext.rotate(by: -.pi)
                ctx.cgContext.translateBy(x: -textImageSize.width / 2, y: -textImageSize.height / 2)
            }
            
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        if let planeNode = planeNode, let plane = planeNode.geometry as? SCNPlane {
            plane.firstMaterial?.diffuse.contents = image
            plane.firstMaterial?.isDoubleSided = true
            plane.firstMaterial?.transparency = SizePanel.alpha
        }
    }
    
    public func updateTransparency(alpha: CGFloat) {
        if let planeNode = planeNode, let plane = planeNode.geometry as? SCNPlane {
            plane.firstMaterial?.transparency = alpha
        }
    }
}
