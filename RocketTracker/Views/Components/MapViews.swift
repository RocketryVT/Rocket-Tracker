//
//  MapViews.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 5/14/25.
//

import SwiftUICore
import Combine
import _MapKit_SwiftUI

// Map view with location tracking
func mapView(for telemetry: TelemetryData, presenter: MainPresenter) -> some View {
    Map(initialPosition: MapCameraPosition.region(presenter.mapRegion)) {
        // Add marker for current position
        Marker("Rocket", coordinate: CLLocationCoordinate2D(
            latitude: telemetry.lat,
            longitude: telemetry.lon
        )).tint(.red)
        
        // Add path for breadcrumb trail
        if presenter.pathCoordinates.count > 1 {
            MapPolyline(coordinates: presenter.pathCoordinates)
                .stroke(.blue, lineWidth: 3)
        }
    }
    .frame(height: 300)
}

// Placeholder map when not connected
var placeholderMapView: some View {
    ZStack {
        // Color(UIColor.secondarySystemBackground)
        Color(Color.secondary.opacity(0.1))
        VStack {
            Image(systemName: "map")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Connect to Rocket Tracker to view location")
                .foregroundColor(.gray)
        }
    }
    .frame(height: 300)
}
