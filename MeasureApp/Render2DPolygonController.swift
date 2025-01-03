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
    
    private var currentScale: CGFloat = 1.0 // 当前缩放比例
    
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
        addPinchGesture(to: polygonView)
        
        if !points3D.isEmpty {
            polygon2DManager.drawMode = drawMode
            polygon2DManager.render3DPolygonTo2D(points3D: points3D, uiView: polygonView)
        }
        
        

    }
    
    @objc
    private func closeController() {
        dismiss(animated: true, completion: nil)
    }
    
    
    // 添加缩放手势
    private
    func addPinchGesture(to view: UIView) {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
    }
    
    // 处理缩放手势
    @objc
    private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
//        guard let polygonView = gesture.view else { return }
//        
//        if gesture.state == .changed || gesture.state == .ended {
//            // 更新缩放比例
//            let scale = gesture.scale
//            currentScale *= scale
//            gesture.scale = 1.0
//            
//            // 清空现有绘制内容
//            polygonView.layer.sublayers?.removeAll()
//            polygonView.subviews.forEach { $0.removeFromSuperview() }
//            
//            // 按新缩放比例重新绘制
//            polygon2DManager.render3DPolygonTo2D(points3D: points3D, uiView: polygonView, scale: currentScale)
//        }
    }

}
