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
    
    private lazy var contentView: UIView = {
        let view = UIView(frame: scrollView.bounds)
        view.backgroundColor = .systemPink
        return view
    }()
    
    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 80, width: self.view.bounds.width, height: 400))
        scrollView.backgroundColor = .systemBlue
        scrollView.minimumZoomScale = 0.8
        scrollView.maximumZoomScale = 2.0
        return scrollView
    }()
    
    private var contentCenter: CGPoint = .zero
    private var contentSize: CGSize = .zero
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        // 添加返回按钮
        let backButton = UIBarButtonItem(title: "Back", style: .plain, target: self, action: #selector(closeController))
        navigationItem.leftBarButtonItem = backButton
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        scrollView.delegate = self
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        
        if !points3D.isEmpty {
            polygon2DManager.drawMode = drawMode
            polygon2DManager.render3DPolygonTo2D(points3D: points3D, uiView: contentView)
        }
    }
    
    @objc
    private func closeController() {
        dismiss(animated: true, completion: nil)
    }
}

extension Render2DPolygonController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return contentView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        contentView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                     y: scrollView.contentSize.height * 0.5 + offsetY)
        
        if scrollView.zoomScale <= 2.0 && scrollView.zoomScale >= 0.8 {
            contentView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            contentView.subviews.forEach { $0.removeFromSuperview() }
            // 重新绘制 2D 图形，更新缩放比例
            polygon2DManager.render3DPolygonTo2D(
                points3D: points3D,
                uiView: contentView,
                scale: scrollView.zoomScale
            )
        }
    }
}
