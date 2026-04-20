//
//  SearchResult.swift
//  BikeDirections
//
//  Created by Mac-aroni on 2/24/26.
//

import Foundation
import CoreLocation

struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    var distance: Double? // in meters
    var totalClimb: Double? // in meters

    var isClimbing: Bool {
        return (totalClimb ?? 0) >= 0
    }

    var formattedDistance: String {
        guard let distance = distance else { return "-- mi" }
        let miles = distance / 1609.34
        return String(format: "%.1f mi", miles)
    }

    var formattedClimb: String {
        guard let totalClimb = totalClimb else { return "-- ft" }
        let feet = abs(totalClimb * 3.28084)
        return String(format: "%.0f ft", feet)
    }
}
