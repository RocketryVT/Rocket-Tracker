//
//  MapViews.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 5/14/25.
//

import SwiftUI
import MapKit

// Map view with location tracking
func mapView(for telemetry: TelemetryData, presenter: MainPresenter) -> some View {
    Group {
        if #available(iOS 17.0, *) {
            // iOS 17+ implementation
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
        } else {
            // iOS 15-16 implementation
            MapView(telemetry: telemetry, pathCoordinates: presenter.pathCoordinates)
                .frame(height: 300)
                .edgesIgnoringSafeArea(.all)
        }
    }
}

// Placeholder map when not connected
var placeholderMapView: some View {
    Group {
        if #available(iOS 17.0, *) {
            // iOS 17+ implementation
            ZStack {
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
        } else {
            // iOS 15-16 implementation
            PlaceholderMapView()
        }
    }
}

// iOS 15-16 Map implementation using UIViewRepresentable
struct MapView: UIViewRepresentable {
    var telemetry: TelemetryData
    var pathCoordinates: [CLLocationCoordinate2D]
    
    // Create the MKMapView
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    // Update the view when data changes
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update the map region to center on the current location
        let coordinate = CLLocationCoordinate2D(
            latitude: telemetry.lat, 
            longitude: telemetry.lon
        )
        
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: true)
        
        // Clear existing annotations and overlays
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
        
        // Add rocket marker
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Rocket"
        mapView.addAnnotation(annotation)
        
        // Add path if available
        if pathCoordinates.count > 1 {
            let polyline = MKPolyline(coordinates: pathCoordinates, count: pathCoordinates.count)
            mapView.addOverlay(polyline)
        }
    }
    
    // Coordinator to handle map delegate methods
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        // Customize polyline appearance
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        // Customize annotation appearance
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            
            let identifier = "RocketMarker"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                (annotationView as? MKMarkerAnnotationView)?.glyphImage = UIImage(systemName: "location.fill")
                (annotationView as? MKMarkerAnnotationView)?.markerTintColor = .red
            } else {
                annotationView?.annotation = annotation
            }
            
            return annotationView
        }
    }
}

// iOS 15-16 placeholder view implementation
struct PlaceholderMapView: View {
    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
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
}
