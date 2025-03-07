//
//  SCNVector3+Extension.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/23.
//

import SceneKit

extension SCNVector3: @retroactive Equatable {
    /// 计算向量的长度
    func length() -> Float {
        return sqrt(x * x + y * y + z * z)
    }

    /// 返回归一化的向量
    func normalized() -> SCNVector3 {
        let len = length()
        guard len > 0 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(x / len, y / len, z / len)
    }

    /// 计算两个向量的点积
    func dot(_ vector: SCNVector3) -> Float {
        return x * vector.x + y * vector.y + z * vector.z
    }

    /// 计算两个向量的叉积
    func cross(_ vector: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            y * vector.z - z * vector.y,
            z * vector.x - x * vector.z,
            x * vector.y - y * vector.x
        )
    }
    
    /// 计算两个 3D 点之间的距离
    func distance(to point: SCNVector3) -> Float {
        let dx = x - point.x
        let dy = y - point.y
        let dz = z - point.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    
    /// 向量减法
    static func +(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x + right.x, left.y + right.y, left.z + right.z)
    }
    
    static func -(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x - right.x, left.y - right.y, left.z - right.z)
    }
    
    static func *(vector: SCNVector3, scalar: Float) -> SCNVector3 {
        return SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
    }
    
    static func /(vector: SCNVector3, scalar: Float) -> SCNVector3 {
        return SCNVector3(vector.x / scalar, vector.y / scalar, vector.z / scalar)
    }
    
    public static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    public static func != (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return !(lhs == rhs)
    }
}

extension SCNQuaternion {
    // 通过轴和角度创建四元数
    init(axis: SCNVector3, angle: Float) {
        let halfAngle = angle / 2
        let sinHalfAngle = sin(halfAngle)
        self.init(
            x: axis.x * sinHalfAngle,
            y: axis.y * sinHalfAngle,
            z: axis.z * sinHalfAngle,
            w: cos(halfAngle)
        )
    }
}

extension float4x4 {
    var translation: SIMD3<Float> {
        get {
            let translation = columns.3
            return [translation.x, translation.y, translation.z]
        }
        set(newValue) {
            columns.3 = [newValue.x, newValue.y, newValue.z, columns.3.w]
        }
    }

    var orientation: simd_quatf {
        return simd_quaternion(self)
    }

    init(uniformScale scale: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scale
        columns.1.y = scale
        columns.2.z = scale
    }
}




extension UIColor {
    convenience init(hex: String) {
        let defaultColor: UIColor = .white
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        
        guard hexString.count == 6 || hexString.count == 8 else {
            self.init(cgColor: defaultColor.cgColor)
            return
        }
        
        let scanner = Scanner(string: hexString)
        var hexNumber: UInt64 = 0
        guard scanner.scanHexInt64(&hexNumber) else {
            self.init(cgColor: defaultColor.cgColor)
            return
        }
        
        let r = CGFloat((hexNumber & 0xFF000000) >> 24) / 255.0
        let g = CGFloat((hexNumber & 0x00FF0000) >> 16) / 255.0
        let b = CGFloat((hexNumber & 0x0000FF00) >> 8) / 255.0
        let a = hexString.count == 8 ? CGFloat(hexNumber & 0x000000FF) / 255.0 : 1.0
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}


extension SCNNode {
    func removeSelf() {
        self.childNodes.forEach { $0.removeFromParentNode() }
        self.removeFromParentNode()
    }
}
