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
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var searchText = "" {
        didSet {
            if !isSelecting {
                performSearch()
            }
        }
    }
    
    @Published var transportType: MKDirectionsTransportType = .walking

    private var isSelecting = false
    private var searchTask: Task<Void, Never>?

    private let locationManager = CLLocationManager()
    private let routeService = RouteService()

    private var routeRetriever: RouteRetriever?
    private weak var bluetoothManager: BluetoothManager?

    private let breakpointTriggerDistance: CLLocationDistance = 20

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
                transportType: self.transportType
            ) else {
                currentInstruction = "No route found"
                return
            }

            routeRetriever = retriever
            routePolyline = retriever.route.polyline
            routeDetails = routeService.readRoute(retriever.route)
            currentInstruction = retriever.currentInstruction
            isNavigating = true
            shouldFitRoute = true
            trackingMode = .follow
            annotations = [destination]
        } catch {
            currentInstruction = "Unable to calculate route"
            print("Route error: \(error)")
        }
    }

    func stopNavigation(resetDestination: Bool = false) {
        routeRetriever = nil
        routePolyline = nil
        routeDetails = nil
        isNavigating = false
        shouldFitRoute = false
        currentInstruction = "Choose a destination to begin"

        if resetDestination {
            selectedDestination = nil
            annotations = []
        }
    }

    func didFitRouteOnMap() {
        shouldFitRoute = false
    }

    func recenterOnUser() {
        trackingMode = .follow

        guard let location = locationManager.location else { return }
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
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

        userCoordinate = latest.coordinate

        if trackingMode != .none {
            region = MKCoordinateRegion(
                center: latest.coordinate,
                span: region.span
            )
        }

        guard isNavigating, let routeRetriever else {
            return
        }

        // 1. Check if we've reached the current breakpoint (the turn)
        if let _ = routeRetriever.advanceIfNeeded(for: latest, threshold: breakpointTriggerDistance) {
            if let nextStep = routeRetriever.getCurrentStep() {
                currentInstruction = nextStep.instructions
            } else {
                currentInstruction = "Arrived at \(selectedDestination?.name ?? "destination")"
                isNavigating = false
                
                // Send an "Arrived" signal (Direction 0, Distance 0)
                bluetoothManager?.sendNavigationUpdate(direction: 0, distance: 0)
                return
            }
        }
        
        // 2. Continuously stream current instruction and distance to the ESP32
        if let distanceToTurn = routeRetriever.distanceToCurrentBreakpoint(from: latest) {
            let normalizedInstruction = currentInstruction.lowercased()
            var directionCode: UInt8 = 0 // Default to 0 (Straight / Continue)
            
            if normalizedInstruction.contains("left") {
                directionCode = 1
            } else if normalizedInstruction.contains("right") {
                directionCode = 2
            }
            
            // Send the stream!
            bluetoothManager?.sendNavigationUpdate(direction: directionCode, distance: Int(distanceToTurn))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
