//
//  Polygon2DManager.swift
//  MeasureApp
//
//  Created by 吴熠 on 2025/1/2.
//

import UIKit
import SceneKit
import ARKit


enum MeasurementUnit {
    case meters
    case centimeters
    case millimeters
    case inches

    func formattedValue(from meters: CGFloat) -> String {
        switch self {
        case .meters:
            return String(format: "%.2f m", meters)
        case .centimeters:
            return String(format: "%d cm", Int(meters * 100))
        case .millimeters:
            return String(format: "%d mm", Int(meters * 1000))
        case .inches:
            return String(format: "%.0f in", meters / 2.54)
        }
    }
}

public struct UIConstants {
    static let labelWidth: CGFloat = 50.0
    static let labelHeight: CGFloat = 20.0
    static let circleRadius: CGFloat = 5.0
    static let labelCornerRadius: CGFloat = 10.0
    static let labelFontSize: CGFloat = 12.0
    static let lineWidth: CGFloat = 2.0
    static let verticalPadding: CGFloat = 80
    static let horizontalPadding: CGFloat = 20
    static let maxScale: CGFloat = 2.0
    static let minScale: CGFloat = 0.8
}


class Polygon2DManager: NSObject {
    
    public var drawMode: MeasureMode = .distance
    
    public var measurementUnit: MeasurementUnit = .centimeters {
        didSet {
            for (label, value) in allSizeLabels {
                label.text = measurementUnit.formattedValue(from: value)
            }
        }
    }
    
    private(set) var area: Float = 0
    private(set) var distance: Float = 0
    
    // 所有尺寸面板集合
    public var allSizeLabels: [UILabel: CGFloat] = [:]
    
    public func render3DPolygonTo2D(
        points3D: [SCNVector3],
        uiView: UIView,
        scale: CGFloat = 1.0
    ) {
        // 1. 将 3D 点投影到局部平面(平面由一个原点 planeOrigin 和法向量 planeNormal 定义,使用点到平面的距离公式，将点调整到平面上)
        var projectedPoints: [CGPoint] = []
        switch drawMode {
        case .distance:
            projectedPoints = projectLineToPlane(points: points3D, planeOrigin: points3D[points3D.count - 1], normal: SCNVector3(0, 1, 0))
        case .area:
            projectedPoints =  projectVerticesTo2D(vertices: points3D)
            area = calculateAreaFrom2DVertices(vertices: projectedPoints)
        }
        
        // 2. 等比缩放并居中到屏幕(计算点集的最小外接矩形,根据视图尺寸计算缩放因子，并应用缩放和位移)
        let scaledPoints = scaleAndCenterPoints(projectedPoints, in: uiView.bounds.size)
        
        
        // 3. 绘制 2D 图形
        draw2DPolygonWithDistanceLabels(points3D: points3D, scaledPoints: scaledPoints, on: uiView, scale: scale)
    }
    
    
    // 获取投影后的 2D 坐标
    private func projectVerticesTo2D(vertices: [SCNVector3]) -> [CGPoint] {
        // 计算法向量
        let normal = calculateNormal(vertices: vertices)
        
        // 选择投影平面
        let projectionPlane = selectProjectionPlane(normal: normal)
        
        // 投影每个点到参考平面
        return vertices.map { projectPoint($0, onto: projectionPlane) }
    }

    
    // 计算法向量
    private func calculateNormal(vertices: [SCNVector3]) -> SCNVector3 {
        let v1 = vertices[1] - vertices[0]
        let v2 = vertices[2] - vertices[0]
        return v1.cross(v2).normalized()
    }
    
    // 选择参考平面（最大法向量分量）
    private func selectProjectionPlane(normal: SCNVector3) -> (x: Int, y: Int) {
        if abs(normal.x) > abs(normal.y) && abs(normal.x) > abs(normal.z) {
            return (1, 2) // YZ 平面
        } else if abs(normal.y) > abs(normal.z) {
            return (0, 2) // XZ 平面
        } else {
            return (0, 1) // XY 平面
        }
    }
    
    // 将点投影到指定平面
    private func projectPoint(_ point: SCNVector3, onto plane: (x: Int, y: Int)) -> CGPoint {
        let coordinates = [point.x, point.y, point.z]
        return CGPoint(x: CGFloat(coordinates[plane.x]), y: CGFloat(coordinates[plane.y]))
    }
    
    
    // 根据投影点计算 2D 多边形面积
    private func calculateAreaFrom2DVertices(vertices: [CGPoint]) -> Float {
        var area: Float = 0
        let count = vertices.count
        for i in 0..<count {
            let current = vertices[i]
            let next = vertices[(i + 1) % count]
            area += Float((current.x * next.y - current.y * next.x))
        }
        return abs(area) / 2
    }
    
    
    
    
    private func projectLineToPlane(points: [SCNVector3], planeOrigin: SCNVector3, normal: SCNVector3) -> [CGPoint] {
        let normalLength = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
        let normalizedNormal = SCNVector3(normal.x / normalLength, normal.y / normalLength, normal.z / normalLength)
        
        return points.map { point in
            let vectorToPoint = SCNVector3(point.x - planeOrigin.x, point.y - planeOrigin.y, point.z - planeOrigin.z)
            let distance = (vectorToPoint.x * normalizedNormal.x +
                            vectorToPoint.y * normalizedNormal.y +
                            vectorToPoint.z * normalizedNormal.z)
            let projectedPoint = SCNVector3(point.x - distance * normalizedNormal.x,
                                            point.y - distance * normalizedNormal.y,
                                            point.z - distance * normalizedNormal.z)
            return CGPoint(x: CGFloat(projectedPoint.x), y: CGFloat(projectedPoint.z)) // 使用 XZ 平面
        }
    }
    
    private func scaleAndCenterPoints(_ points: [CGPoint], in viewSize: CGSize) -> [CGPoint] {
        // 计算点集的最小外接矩形
        guard let minX = points.map({ $0.x }).min(),
              let maxX = points.map({ $0.x }).max(),
              let minY = points.map({ $0.y }).min(),
              let maxY = points.map({ $0.y }).max() else { return [] }
        
        // 1. 计算点集的宽高
        let pointsWidth = maxX - minX
        let pointsHeight = maxY - minY
        
        // 2. 计算视图的宽高减去边距
        let viewWidth = viewSize.width - UIConstants.horizontalPadding
        let viewHeight = viewSize.height - UIConstants.verticalPadding
        
        // 计算等比缩放因子
        let scaleX = viewWidth / pointsWidth
        let scaleY = viewHeight / pointsHeight
        let finalScale = min(scaleX, scaleY) // 取宽高的最小缩放比例，保持等比缩放。
        
        // 缩放并居中
        let offsetX = (viewWidth - pointsWidth * finalScale) / 2
        let offsetY = (viewHeight - pointsHeight * finalScale) / 2
        
        return points.map { point in
            CGPoint(
                x: (point.x - minX) * finalScale + offsetX + UIConstants.horizontalPadding / 2.0,
                y: (point.y - minY) * finalScale + offsetY + UIConstants.verticalPadding / 2.0
            )
        }
    }
    
    
    private func draw2DPolygonWithDistanceLabels(
        points3D: [SCNVector3],
        scaledPoints: [CGPoint],
        on view: UIView,
        scale: CGFloat
    ) {
        guard points3D.count == scaledPoints.count, points3D.count > 1 else { return }
        
        let path = UIBezierPath()
        path.move(to: scaledPoints.first!)
        
        switch drawMode {
        case .distance:
            // 将点两两分组，并存入数组
            var lineSegments: [(start: SCNVector3, end: SCNVector3)] = []
            for i in stride(from: 0, to: points3D.count - 1, by: 2) {
                let start = points3D[i]
                let end = points3D[i + 1]
                lineSegments.append((start: start, end: end))
            }
            // 绘制每一段线段
            for segment in lineSegments {
                if let start = points3D.firstIndex(of: segment.start), let end = points3D.firstIndex(of: segment.end) {
                    let start2D = scaledPoints[start]
                    let end2D = scaledPoints[end]
                    // 计算 3D 距离
                    let distance = segment.start.distance(to: segment.end)
                    self.distance += distance
                    drawLineWithMeasurements(from: start2D, to: end2D, distance: CGFloat(distance), on: view, scale: scale)
                }
    
            }
        case .area:
            for i in 0..<points3D.count {
                let current2DPoint = scaledPoints[i]
                let next2DPoint = scaledPoints[(i + 1) % scaledPoints.count]
                if current2DPoint != next2DPoint {
                    let current3DPoint = points3D[i]
                    let next3DPoint = points3D[(i + 1) % points3D.count]
                    let distance = current3DPoint.distance(to: next3DPoint)
                    drawLineWithMeasurements(from: current2DPoint, to: next2DPoint, distance: CGFloat(distance), on: view, scale: scale)
                }
            }
        }
        
        
    }
    
    
    // 绘制线段和标注
    private func drawLineWithMeasurements(
        from point1: CGPoint,
        to point2: CGPoint,
        distance: CGFloat,
        on view: UIView,
        scale: CGFloat
    ) {
        // 1. 绘制线段
        let linePath = UIBezierPath()
        linePath.move(to: point1)
        linePath.addLine(to: point2)
        
        let lineLayer = CAShapeLayer()
        lineLayer.path = linePath.cgPath
        lineLayer.strokeColor = UIColor.systemGreen.cgColor
        lineLayer.lineWidth = UIConstants.lineWidth / scale
        view.layer.addSublayer(lineLayer)
        
        // 2. 绘制两端的实心圆
        drawSolidCircle(at: point1, on: view, scale: scale)
        drawSolidCircle(at: point2, on: view, scale: scale)
        
        // 3. 添加尺寸标注面板
        addMeasurementLabel(from: point1, to: point2, distance: distance, on: view, scale: scale)
    }
    
    // 绘制实心圆
    private func drawSolidCircle(at point: CGPoint, on view: UIView, scale: CGFloat) {
        let circleRadius = UIConstants.circleRadius / scale
        let circlePath = UIBezierPath(
            arcCenter: point,
            radius: circleRadius,
            startAngle: 0,
            endAngle: CGFloat.pi * 2,
            clockwise: true
        )
        
        let circleLayer = CAShapeLayer()
        circleLayer.path = circlePath.cgPath
        circleLayer.fillColor = UIColor.systemGreen.cgColor
        view.layer.addSublayer(circleLayer)
    }
    
    // 添加尺寸标注面板
    private func addMeasurementLabel(
        from point1: CGPoint,
        to point2: CGPoint,
        distance: CGFloat,
        on view: UIView,
        scale: CGFloat
    ) {
        // 计算中点
        let midX = (point1.x + point2.x) / 2
        let midY = (point1.y + point2.y) / 2
        let midpoint = CGPoint(x: midX, y: midY)
        
        // 创建标注背景
        let labelWidth = UIConstants.labelWidth / scale
        let labelHeight = UIConstants.labelHeight / scale
        let labelBackground = UIView(frame: CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight))
        labelBackground.center = midpoint
        labelBackground.backgroundColor = UIColor.systemGreen
        labelBackground.layer.cornerRadius = (UIConstants.labelHeight / 2.0) / scale
        view.addSubview(labelBackground)
        
        // 添加尺寸文本
        let distanceLabel = UILabel(frame: labelBackground.bounds)
        distanceLabel.text = measurementUnit.formattedValue(from: distance)
        distanceLabel.font = UIFont.systemFont(ofSize: UIConstants.labelFontSize / scale)
        distanceLabel.textAlignment = .center
        distanceLabel.textColor = .white
        labelBackground.addSubview(distanceLabel)
        self.allSizeLabels[distanceLabel] = distance
        
        // 旋转标注，使其与线段平行
        let angle = atan2(point2.y - point1.y, point2.x - point1.x)
        // 保证文字永远正向
        if angle > CGFloat.pi / 2 || angle < -CGFloat.pi / 2 {
            // 如果角度在 90° ~ 270°，需要额外旋转 180°
            labelBackground.transform = CGAffineTransform(rotationAngle: angle + CGFloat.pi)
        } else {
            // 角度在 -90° ~ 90°，直接旋转即可
            labelBackground.transform = CGAffineTransform(rotationAngle: angle)
        }
    }
    
    public func clearContent(in uiView: UIView) {
        uiView.layer.sublayers?.removeAll()
        uiView.subviews.forEach { $0.removeFromSuperview() }
    }
    
}
