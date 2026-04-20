import SwiftUI
import MapKit
import CoreLocation
internal import Combine

final class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7756, longitude: -84.3963),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    @Published var annotations: [SearchResult] = []
    @Published var trackingMode: MapUserTrackingMode = .follow
    @Published var selectedDestination: SearchResult?
    @Published var results: [SearchResult] = []

    @Published var routePolyline: MKPolyline?
    @Published var routeDetails: RouteDetails?
    @Published var currentInstruction = "Choose a destination to begin"
    @Published var isNavigating = false
    @Published var shouldFitRoute = false
    @Published var shouldRecenter = false
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var searchText = "" {
        didSet {
            if !isSelecting {
                performSearch()
            }
        }
    }

    @Published var transportType: MKDirectionsTransportType = .cycling

    private var isSelecting = false
    private var searchTask: Task<Void, Never>?
    private var rerouteTask: Task<Void, Never>?
    private var isRerouting = false
    private var lastRerouteAt: Date?

    private let locationManager = CLLocationManager()
    private let routeService = RouteService()

    private var routeRetriever: RouteRetriever?
    private weak var bluetoothManager: BluetoothManager?

    private let breakpointTriggerDistance: CLLocationDistance = 20
    private let offRouteThreshold: CLLocationDistance = 60
    private let rerouteCooldown: TimeInterval = 12

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func attachBluetoothManager(_ bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    func performSearch() {
        searchTask?.cancel()

        if let dest = selectedDestination, searchText == dest.name {
            return
        }

        selectedDestination = nil
        annotations = []
        routePolyline = nil
        routeDetails = nil
        routeRetriever = nil
        isNavigating = false
        currentInstruction = "Choose a destination to begin"

        guard !searchText.isEmpty else {
            self.results = []
            return
        }

        searchTask = Task { @MainActor in
            if Task.isCancelled || selectedDestination != nil { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchText
            request.region = region

            let search = MKLocalSearch(request: request)

            do {
                let response = try await search.start()
                let userLocation = locationManager.location

                if !self.isSelecting && self.selectedDestination == nil {
                    self.results = response.mapItems.compactMap { item in
                        var result = SearchResult(
                            name: item.name ?? "",
                            subtitle: item.placemark.title ?? "",
                            coordinate: item.placemark.coordinate
                        )

                        if let userLoc = userLocation {
                            let destLoc = CLLocation(
                                latitude: result.coordinate.latitude,
                                longitude: result.coordinate.longitude
                            )
                            result.distance = userLoc.distance(from: destLoc)
                        }

                        result.totalClimb = Double.random(in: -50...50)
                        return result
                    }
                }
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("Search error: \(error)")
                }
                self.results = []
            }
        }
    }

    func selectResult(_ result: SearchResult) {
        stopNavigation(resetDestination: false)

        isSelecting = true
        searchText = result.name
        isSelecting = false

        annotations = [result]
        selectedDestination = result
        results = []

        region = MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    @MainActor
    func startRoute() async {
        guard let destination = selectedDestination else { return }

        do {
            guard let retriever = try await routeService.fetchRouteRetriever(
                for: destination,
                from: locationManager.location?.coordinate,
                transportType: transportType
            ) else {
                currentInstruction = "No route found"
                return
            }

            applyRoute(retriever.route, retriever: retriever, fitOnMap: true)

            if let location = locationManager.location {
                streamNavigationUpdate(from: location)
            }
        } catch {
            currentInstruction = "Unable to calculate route"
            print("Route error: \(error)")
        }
    }

    func stopNavigation(resetDestination: Bool = false) {
        rerouteTask?.cancel()
        rerouteTask = nil
        isRerouting = false
        routeRetriever = nil
        routePolyline = nil
        routeDetails = nil
        isNavigating = false
        shouldFitRoute = false
        shouldRecenter = false
        currentInstruction = "Choose a destination to begin"

        if resetDestination {
            selectedDestination = nil
            annotations = []
        }
    }

    func didFitRouteOnMap() {
        shouldFitRoute = false
    }

    func didRecenterMap() {
        shouldRecenter = false
    }

    func recenterOnUser() {
        trackingMode = .follow

        guard let location = locationManager.location else { return }
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        shouldRecenter = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        guard latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= 35 else { return }

        userCoordinate = latest.coordinate

        guard isNavigating, let routeRetriever else {
            return
        }

        if shouldReroute(for: latest, routeRetriever: routeRetriever) {
            reroute(from: latest)
            return
        }

        if routeRetriever.advanceIfNeeded(for: latest, threshold: breakpointTriggerDistance) {
            routePolyline = routeRetriever.remainingPolyline ?? routeRetriever.route.polyline

            if routeRetriever.hasArrived {
                currentInstruction = "Arrived at \(selectedDestination?.name ?? "destination")"
                isNavigating = false
                routePolyline = nil
                bluetoothManager?.sendNavigationUpdate(direction: 0, distance: 0)
                return
            }
        }

        streamNavigationUpdate(from: latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    private func applyRoute(_ route: MKRoute, retriever: RouteRetriever, fitOnMap: Bool) {
        routeRetriever = retriever
        routePolyline = retriever.remainingPolyline ?? route.polyline
        routeDetails = routeService.readRoute(route)
        currentInstruction = retriever.currentInstruction
        isNavigating = true
        shouldFitRoute = fitOnMap
        trackingMode = .follow

        if let destination = selectedDestination {
            annotations = [destination]
        }
    }

    private func shouldReroute(for location: CLLocation, routeRetriever: RouteRetriever) -> Bool {
        guard selectedDestination != nil else {
            return false
        }

        if isRerouting {
            return false
        }

        if let lastRerouteAt,
           Date().timeIntervalSince(lastRerouteAt) < rerouteCooldown {
            return false
        }

        let distanceFromRoute = routeRetriever.route.polyline.distance(to: location)
        return distanceFromRoute > offRouteThreshold
    }

    private func reroute(from location: CLLocation) {
        guard !isRerouting, let destination = selectedDestination else {
            return
        }

        rerouteTask?.cancel()
        isRerouting = true
        lastRerouteAt = Date()
        currentInstruction = "Rerouting..."

        rerouteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRerouting = false
                self.rerouteTask = nil
            }

            do {
                guard let retriever = try await routeService.fetchRouteRetriever(
                    for: destination,
                    from: location.coordinate,
                    transportType: transportType
                ) else {
                    currentInstruction = "No route found"
                    return
                }

                applyRoute(retriever.route, retriever: retriever, fitOnMap: true)
                streamNavigationUpdate(from: location)
            } catch {
                if Task.isCancelled { return }
                currentInstruction = "Unable to reroute"
                print("Reroute error: \(error)")
            }
        }
    }

    private func streamNavigationUpdate(from location: CLLocation) {
        guard let routeRetriever,
              let distanceToTurn = routeRetriever.distanceToCurrentBreakpoint(from: location) else {
            return
        }

        let instruction = routeRetriever.currentInstruction
        currentInstruction = instruction
        let bucketedDistance = max(0, (Int(distanceToTurn) / 5) * 5)

        bluetoothManager?.sendNavigationUpdate(
            direction: directionCode(for: instruction),
            distance: bucketedDistance
        )
    }

    private func directionCode(for instruction: String) -> UInt8 {
        let normalizedInstruction = instruction.lowercased()

        if normalizedInstruction.contains("left") {
            return 1
        }

        if normalizedInstruction.contains("right") {
            return 2
        }

        return 0
    }
}
