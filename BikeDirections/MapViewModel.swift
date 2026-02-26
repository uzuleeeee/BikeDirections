//
//  MapViewModel.swift
//  BikeDirections
//
//  Created by Mac-aroni on 2/24/26.
//

import SwiftUI
import MapKit
import CoreLocation
internal import Combine

class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7756, longitude: -84.3963),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    
    @Published var annotations: [SearchResult] = []
    @Published var trackingMode: MapUserTrackingMode = .follow
    @Published var selectedDestination: SearchResult?
    
    private var isSelecting = false
    
    private let locationManager = CLLocationManager()
    
    @Published var searchText = "" {
        didSet {
            // Only perform a search if the user is actually typing
            if !isSelecting {
                performSearch()
            }
        }
    }
    
    @Published var results: [SearchResult] = []
    
    private var searchTask: Task<Void, Never>?
    
    override init() {
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func performSearch() {
        searchTask?.cancel()
        
        if let dest = selectedDestination, searchText == dest.name {
            return
        }
        
        selectedDestination = nil
        
        annotations = []
        
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
                            let destLoc = CLLocation(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude)
                            result.distance = userLoc.distance(from: destLoc)
                        }
                        
                        // TODO: Replace with actual climb
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
        isSelecting = true
        searchText = result.name
        isSelecting = false
        
        self.annotations = [result]
        self.selectedDestination = result
        
        results = []
        selectedDestination = result
        
        region = MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }
}
