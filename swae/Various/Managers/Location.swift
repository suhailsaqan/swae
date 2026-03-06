import CoreLocation
import Foundation

private class BackgroundActivity {
    private var backgroundSession: Any?

    func start() {
        if #available(iOS 17.0, *) {
            backgroundSession = CLBackgroundActivitySession()
        }
    }

    func stop() {
        if #available(iOS 17.0, *) {
            if let session = backgroundSession as? CLBackgroundActivitySession {
                session.invalidate()
            }
        }
    }
}

class Location: NSObject {
    private var manager = CLLocationManager()
    private var onUpdate: ((CLLocation) -> Void)?
    private var latestLocation: CLLocation?
    private var backgroundActivity = BackgroundActivity()

    func start(
        accuracy: SettingsLocationDesiredAccuracy,
        distanceFilter: SettingsLocationDistanceFilter,
        onUpdate: @escaping (CLLocation) -> Void
    ) {
        logger.debug(
            "location: Start with accuracy \(accuracy) and distance filter \(distanceFilter)")
        self.onUpdate = onUpdate
        manager.delegate = self
        switch accuracy {
        case .best:
            manager.desiredAccuracy = kCLLocationAccuracyBest
        case .nearestTenMeters:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case .hundredMeters:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        switch distanceFilter {
        case .none:
            manager.distanceFilter = kCLDistanceFilterNone
        case .oneMeter:
            manager.distanceFilter = 1
        case .threeMeters:
            manager.distanceFilter = 3
        case .fiveMeters:
            manager.distanceFilter = 5
        case .tenMeters:
            manager.distanceFilter = 10
        case .twentyMeters:
            manager.distanceFilter = 20
        case .fiftyMeters:
            manager.distanceFilter = 50
        case .hundredMeters:
            manager.distanceFilter = 100
        case .twoHundredMeters:
            manager.distanceFilter = 200
        }
        // Check current authorization status and handle accordingly
        switch manager.authorizationStatus {
        case .notDetermined:
            logger.debug("location: Requesting authorization")
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            logger.warning("location: Location access denied or restricted")
        case .authorizedWhenInUse, .authorizedAlways:
            logger.debug("location: Already authorized, starting location updates")
            manager.startUpdatingLocation()
        @unknown default:
            logger.warning("location: Unknown authorization status, requesting permission")
            manager.requestWhenInUseAuthorization()
        }

        backgroundActivity.start()
    }

    func stop() {
        logger.debug("location: Stop")
        onUpdate = nil
        manager.stopUpdatingLocation()
        backgroundActivity.stop()
    }

    func status() -> String {
        guard let latestLocation else {
            return ""
        }
        return format(speed: latestLocation.speed)
    }

    func getLatestKnownLocation() -> CLLocation? {
        return latestLocation
    }

    func isAuthorized() -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    func getAuthorizationStatus() -> CLAuthorizationStatus {
        return manager.authorizationStatus
    }

    func requestPermissionIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            logger.debug("location: Requesting permission")
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            logger.warning("location: Permission denied - user needs to enable in Settings")
        case .authorizedWhenInUse, .authorizedAlways:
            logger.debug("location: Already authorized")
        @unknown default:
            logger.warning("location: Unknown status, requesting permission")
            manager.requestWhenInUseAuthorization()
        }
    }
}

extension Location: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        logger.debug("location: Auth did change \(manager.authorizationStatus)")

        switch manager.authorizationStatus {
        case .notDetermined:
            logger.debug("location: Permission not determined, requesting authorization")
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            logger.warning("location: Permission denied or restricted")
        case .authorizedWhenInUse, .authorizedAlways:
            logger.debug("location: Permission granted, starting location updates")
            if onUpdate != nil {
                manager.startUpdatingLocation()
            }
        @unknown default:
            logger.warning("location: Unknown authorization status")
        }
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        logger.error("location: Error \(error)")

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                logger.error("location: Access denied - check app permissions in Settings")
            case .locationUnknown:
                logger.warning("location: Location service unable to determine location")
            case .network:
                logger.error("location: Network error while getting location")
            default:
                logger.error("location: Other location error: \(clError.localizedDescription)")
            }
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            latestLocation = location
            onUpdate?(location)
        }
    }
}
