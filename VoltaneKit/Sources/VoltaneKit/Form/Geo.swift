import Foundation

/// 定位匹配常用地点：距离不超过 300 米的最近一个。
public enum Geo {
    public static let matchRadius = 300.0

    public static func haversine(_ a1: Double, _ o1: Double, _ a2: Double, _ o2: Double) -> Double {
        let r = 6_371_000.0
        func rad(_ x: Double) -> Double { x * .pi / 180 }
        let d = pow(sin(rad(a2 - a1) / 2), 2) + cos(rad(a1)) * cos(rad(a2)) * pow(sin(rad(o2 - o1) / 2), 2)
        return 2 * r * asin(sqrt(d))
    }

    public static func nearest(lat: Double, lng: Double, in places: [Place]) -> (place: Place, distance: Double)? {
        var best: (Place, Double)?
        for p in places {
            guard let plat = p.lat, let plng = p.lng else { continue }
            let d = haversine(lat, lng, plat, plng)
            if best == nil || d < best!.1 { best = (p, d) }
        }
        guard let best, best.1 < matchRadius else { return nil }
        return (best.0, best.1)
    }
}
