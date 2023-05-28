import Foundation
import CoreLocation

struct Location {
    var heading: Double
    var speed: Double
    var horizontalAccuracy: Double
}

protocol LocationUpdateDelegate: AnyObject {
    func didUpdateLocation(location: Location)
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: Location?
    private var delegates: [LocationUpdateDelegate] = []
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    func addDelegate(_ delegate: LocationUpdateDelegate) {
        delegates.append(delegate)
    }

    func requestLocationPermission() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.distanceFilter = 1
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    // CLLocationManagerDelegate methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            let newLocation = Location(heading: location.course, speed: location.speed, horizontalAccuracy: location.horizontalAccuracy )
            currentLocation = newLocation
            delegates.forEach { $0.didUpdateLocation(location: newLocation) }
        }
    }
}
