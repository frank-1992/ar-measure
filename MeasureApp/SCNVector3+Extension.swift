//
//  SCNVector3+Extension.swift
//  MeasureApp
//
//  Created by 吴熠 on 2024/12/23.
//

import SceneKit

extension SCNVector3 {
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
    
    /// 向量减法
    public static func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        return SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }
    
    /// 计算两个 3D 点之间的距离
    func distance(to vector: SCNVector3) -> Float {
        return sqrt(pow(x - vector.x, 2) + pow(y - vector.y, 2) + pow(z - vector.z, 2))
    }
    
    public static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    public static func != (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return !(lhs == rhs)
    }
}

