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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
