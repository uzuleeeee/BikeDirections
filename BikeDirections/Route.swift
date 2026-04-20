import Foundation
import MapKit
import CoreLocation

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
    func fetchRoute(
        for sr: SearchResult,
        from sourceCoordinate: CLLocationCoordinate2D? = nil,
        transportType: MKDirectionsTransportType = .cycling
    ) async throws -> MKRoute? {
        let destination = MKMapItem(
            placemark: MKPlacemark(coordinate: sr.coordinate)
        )

        let request = MKDirections.Request()
        if let sourceCoordinate {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: sourceCoordinate))
        } else {
            request.source = MKMapItem.forCurrentLocation()
        }
        request.destination = destination
        request.transportType = transportType
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        return response.routes.min { $0.expectedTravelTime < $1.expectedTravelTime }
    }

    func fetchRouteRetriever(
        for sr: SearchResult,
        from sourceCoordinate: CLLocationCoordinate2D? = nil,
        transportType: MKDirectionsTransportType = .cycling
    ) async throws -> RouteRetriever? {
        guard let route = try await fetchRoute(
            for: sr,
            from: sourceCoordinate,
            transportType: transportType
        ) else {
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

final class RouteRetriever {
    let route: MKRoute
    private let navigableSteps: [MKRoute.Step]
    private(set) var currentSegmentIndex = 0

    init(route: MKRoute) {
        self.route = route
        self.navigableSteps = route.steps.filter { step in
            !step.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            step.polyline.pointCount > 0
        }
    }

    var hasSteps: Bool {
        !navigableSteps.isEmpty
    }

    var totalStepCount: Int {
        navigableSteps.count
    }

    private var currentSegmentStep: MKRoute.Step? {
        guard navigableSteps.indices.contains(currentSegmentIndex) else {
            return nil
        }
        return navigableSteps[currentSegmentIndex]
    }

    var currentInstruction: String {
        currentSegmentStep?.instructions ?? "Continue"
    }

    var hasArrived: Bool {
        currentSegmentIndex >= navigableSteps.count
    }

    var currentBreakpointCoordinate: CLLocationCoordinate2D? {
        currentSegmentStep?.polyline.lastCoordinate
    }

    func distanceToCurrentBreakpoint(from location: CLLocation) -> CLLocationDistance? {
        guard let coordinate = currentBreakpointCoordinate else {
            return nil
        }

        let breakpoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: breakpoint)
    }

    @discardableResult
    func advanceIfNeeded(for location: CLLocation, threshold: CLLocationDistance = 20) -> Bool {
        guard let distance = distanceToCurrentBreakpoint(from: location),
              distance <= threshold else {
            return false
        }

        currentSegmentIndex += 1
        return true
    }

    var remainingPolyline: MKPolyline? {
        guard !hasArrived else {
            return nil
        }

        let remainingCoordinates = navigableSteps
            .dropFirst(currentSegmentIndex)
            .flatMap { $0.polyline.coordinates }

        guard !remainingCoordinates.isEmpty else {
            return nil
        }

        return MKPolyline(coordinates: remainingCoordinates, count: remainingCoordinates.count)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        guard pointCount > 0 else {
            return []
        }

        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }

    var lastCoordinate: CLLocationCoordinate2D? {
        coordinates.last
    }

    func distance(to location: CLLocation) -> CLLocationDistance {
        let coordinates = self.coordinates
        guard !coordinates.isEmpty else {
            return .greatestFiniteMagnitude
        }

        if coordinates.count == 1 {
            let onlyPoint = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
            return location.distance(from: onlyPoint)
        }

        let userPoint = MKMapPoint(location.coordinate)
        var minimumDistance = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<(coordinates.count - 1) {
            let start = MKMapPoint(coordinates[index])
            let end = MKMapPoint(coordinates[index + 1])
            let closestPoint = userPoint.closestPoint(onSegmentFrom: start, to: end)
            let distance = userPoint.distance(to: closestPoint)
            minimumDistance = min(minimumDistance, distance)
        }

        return minimumDistance
    }
}

private extension MKMapPoint {
    func closestPoint(onSegmentFrom start: MKMapPoint, to end: MKMapPoint) -> MKMapPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let segmentLengthSquared = (dx * dx) + (dy * dy)

        guard segmentLengthSquared > 0 else {
            return start
        }

        let projection = ((x - start.x) * dx + (y - start.y) * dy) / segmentLengthSquared
        let clampedProjection = min(max(projection, 0), 1)

        return MKMapPoint(
            x: start.x + (clampedProjection * dx),
            y: start.y + (clampedProjection * dy)
        )
    }
}
