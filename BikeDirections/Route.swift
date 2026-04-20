import Foundation
import MapKit
import CoreLocation

// RouteDetails remains exactly the same
struct RouteDetails {
    let name: String
    let distanceMeters: Double
    let expectedTravelTimeSeconds: TimeInterval
    let steps: [String]

    var distanceMiles: Double {
        distanceMeters / 1609.34
    }

    var formattedDistance: String {
        String(format: "%.1f mi", distanceMiles)
    }

    var formattedTravelTime: String {
        let minutes = expectedTravelTimeSeconds / 60

        if minutes < 60 {
            return String(format: "%.0f min", minutes)
        }

        let hours = Int(minutes) / 60
        let remainingMinutes = Int(minutes) % 60
        return "\(hours) hr \(remainingMinutes) min"
    }
}

final class RouteService {
    // 1. Add transportType parameter (default to .walking for biking proxy)
    func fetchRoute(for sr: SearchResult, transportType: MKDirectionsTransportType = .walking) async throws -> MKRoute? {
        let destination = MKMapItem(
            placemark: MKPlacemark(coordinate: sr.coordinate)
        )

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        
        // 2. Apply the dynamic transport type instead of hardcoded .automobile
        request.transportType = transportType

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        return response.routes.first
    }

    // 3. Pass the transport type through the retriever fetcher
    func fetchRouteRetriever(for sr: SearchResult, transportType: MKDirectionsTransportType = .walking) async throws -> RouteRetriever? {
        guard let route = try await fetchRoute(for: sr, transportType: transportType) else {
            return nil
        }

        return RouteRetriever(route: route)
    }

    func readRoute(_ route: MKRoute) -> RouteDetails {
        let cleanedSteps = route.steps
            .map { $0.instructions.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return RouteDetails(
            name: route.name,
            distanceMeters: route.distance,
            expectedTravelTimeSeconds: route.expectedTravelTime,
            steps: cleanedSteps
        )
    }
}

// RouteRetriever and MKPolyline extension remain exactly the same
final class RouteRetriever {
    let route: MKRoute
    private let navigableSteps: [MKRoute.Step]
    private(set) var currentStep: Int

    init(route: MKRoute, currentStep: Int = 0) {
        self.route = route
        self.navigableSteps = route.steps.filter { step in
            !step.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            step.polyline.pointCount > 0
        }

        if navigableSteps.isEmpty {
            self.currentStep = 0
        } else {
            self.currentStep = min(max(currentStep, 0), navigableSteps.count - 1)
        }
    }

    var hasSteps: Bool {
        !navigableSteps.isEmpty
    }

    var totalStepCount: Int {
        navigableSteps.count
    }

    var currentRouteStep: MKRoute.Step? {
        guard navigableSteps.indices.contains(currentStep) else {
            return nil
        }
        return navigableSteps[currentStep]
    }

    var currentInstruction: String {
        currentRouteStep?.instructions ?? "Continue"
    }

    var currentBreakpointCoordinate: CLLocationCoordinate2D? {
        currentRouteStep?.polyline.lastCoordinate
    }

    func getCurrentStep() -> MKRoute.Step? {
        currentRouteStep
    }

    func nextStep() -> MKRoute.Step? {
        let nextIndex = currentStep + 1
        guard navigableSteps.indices.contains(nextIndex) else {
            currentStep = navigableSteps.count
            return nil
        }

        currentStep = nextIndex
        return navigableSteps[currentStep]
    }

    func prevStep() -> MKRoute.Step? {
        let previousIndex = currentStep - 1
        guard navigableSteps.indices.contains(previousIndex) else {
            return nil
        }

        currentStep = previousIndex
        return navigableSteps[currentStep]
    }

    func distanceToCurrentBreakpoint(from location: CLLocation) -> CLLocationDistance? {
        guard let coordinate = currentBreakpointCoordinate else {
            return nil
        }

        let breakpoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: breakpoint)
    }

    @discardableResult
    func advanceIfNeeded(for location: CLLocation, threshold: CLLocationDistance = 20) -> MKRoute.Step? {
        guard let distance = distanceToCurrentBreakpoint(from: location), distance <= threshold else {
            return nil
        }

        let reachedStep = currentRouteStep
        _ = nextStep()
        return reachedStep
    }
}

private extension MKPolyline {
    var lastCoordinate: CLLocationCoordinate2D? {
        guard pointCount > 0 else {
            return nil
        }

        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.last
    }
}
