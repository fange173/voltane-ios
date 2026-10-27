import CoreLocation
import Foundation

/// 一次性定位，用来在记录表单里自动选中 300 米内最近的常用地点。只在「使用期间」授权。
@MainActor
final class LocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// `askPermission` 为 false 时，没授权就直接返回 nil，不弹系统提示。
    func locate(askPermission: Bool) async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            guard askPermission else { return nil }
            manager.requestWhenInUseAuthorization()
            for _ in 0..<40 where manager.authorizationStatus == .notDetermined { try? await Task.sleep(for: .milliseconds(250)) }
        }
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.continuation?.resume(returning: loc); self.continuation = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.continuation?.resume(returning: nil); self.continuation = nil }
    }
}
