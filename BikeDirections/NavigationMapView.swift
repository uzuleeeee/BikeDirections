import SwiftUI
import MapKit

struct NavigationMapView: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.setRegion(viewModel.region, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let targetTrackingMode = viewModel.trackingMode.mkTrackingMode
        if mapView.userTrackingMode != targetTrackingMode {
            mapView.setUserTrackingMode(targetTrackingMode, animated: true)
        }

        syncAnnotations(on: mapView, coordinator: context.coordinator)
        syncRoute(on: mapView, coordinator: context.coordinator)

        if viewModel.shouldFitRoute, let routePolyline = viewModel.routePolyline {
            mapView.setVisibleMapRect(
                routePolyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 140, left: 40, bottom: 220, right: 40),
                animated: true
            )
            DispatchQueue.main.async {
                viewModel.didFitRouteOnMap()
            }
        } else if viewModel.shouldRecenter {
            mapView.setRegion(viewModel.region, animated: true)
            DispatchQueue.main.async {
                viewModel.didRecenterMap()
            }
        }
    }

    private func syncAnnotations(on mapView: MKMapView, coordinator: Coordinator) {
        let targetKeys = Set(viewModel.annotations.map { "\($0.name)-\($0.coordinate.latitude)-\($0.coordinate.longitude)" })
        guard targetKeys != coordinator.annotationKeys else { return }

        coordinator.annotationKeys = targetKeys

        let nonUserAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(nonUserAnnotations)

        let destinationAnnotations = viewModel.annotations.map { result -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = result.coordinate
            annotation.title = result.name
            annotation.subtitle = result.subtitle
            return annotation
        }

        mapView.addAnnotations(destinationAnnotations)
    }

    private func syncRoute(on mapView: MKMapView, coordinator: Coordinator) {
        let isSameOverlay: Bool = {
            switch (coordinator.routeOverlay, viewModel.routePolyline) {
            case (nil, nil):
                return true
            case let (existing?, current?):
                return existing === current
            default:
                return false
            }
        }()

        guard !isSameOverlay else { return }

        if let oldOverlay = coordinator.routeOverlay {
            mapView.removeOverlay(oldOverlay)
        }

        coordinator.routeOverlay = viewModel.routePolyline

        if let routePolyline = viewModel.routePolyline {
            mapView.addOverlay(routePolyline)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NavigationMapView
        var routeOverlay: MKPolyline?
        var annotationKeys: Set<String> = []

        init(_ parent: NavigationMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.viewModel.region = mapView.region
        }
    }
}

private extension MapUserTrackingMode {
    var mkTrackingMode: MKUserTrackingMode {
        switch self {
        case .none:
            return .none
        case .follow:
            return .follow
        case .followWithHeading:
            return .followWithHeading
        @unknown default:
            return .follow
        }
    }
}
