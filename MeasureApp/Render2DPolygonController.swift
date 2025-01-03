//
//  Render2DPolygonController.swift
//  MeasureApp
//
//  Created by 吴熠 on 2025/1/2.
//

import UIKit
import SceneKit

class Render2DPolygonController: UIViewController {

    private var polygon2DManager = Polygon2DManager()
    
    public var points3D: [SCNVector3] = []
    
    public var drawMode: DrawMode = .line
    
    private lazy var polygonView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 100, width: self.view.bounds.size.width, height: 400))
        view.backgroundColor = .systemPink
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        // 添加返回按钮
        let backButton = UIBarButtonItem(title: "Back", style: .plain, target: self, action: #selector(closeController))
        navigationItem.leftBarButtonItem = backButton
        
        view.addSubview(polygonView)
        
        if !points3D.isEmpty {
            polygon2DManager.drawMode = drawMode
            polygon2DManager.render3DPolygonTo2D(points3D: points3D, uiView: polygonView)
        }
        
        

    }
    
    @objc
    private func closeController() {
        dismiss(animated: true, completion: nil)
    }
    
    

}
