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

                // Add user location marker
                if let userLocation = presenter.userLocation {
                    UserAnnotation()
                    
                    // Add direction line to rocket
                    if presenter.headingToRocket != nil {
                        MapPolyline(coordinates: [userLocation, CLLocationCoordinate2D(
                            latitude: telemetry.lat,
                            longitude: telemetry.lon
                        )])
                        .stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapUserLocationButton()
            }
            .frame(height: 300)
        } else {
            // iOS 15-16 implementation
             MapView(
                telemetry: telemetry,
                pathCoordinates: presenter.pathCoordinates,
                userLocation: presenter.userLocation,
                headingToRocket: presenter.headingToRocket
            )
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

// iOS 15-16 Map implementation using UIViewRepresentable// Update the MapView struct parameters
struct MapView: UIViewRepresentable {
    var telemetry: TelemetryData
    var pathCoordinates: [CLLocationCoordinate2D]
    var userLocation: CLLocationCoordinate2D?
    var headingToRocket: Double?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true // Enable blue dot for user location
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update the map region to center on the current location
        let rocketCoordinate = CLLocationCoordinate2D(
            latitude: telemetry.lat, 
            longitude: telemetry.lon
        )
        
        // Choose which coordinate to center on (rocket by default)
        let centerCoordinate = rocketCoordinate
        
        let region = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        mapView.setRegion(region, animated: true)
        
        // Clear existing annotations and overlays
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        mapView.removeOverlays(mapView.overlays)
        
        // Add rocket marker
        let rocketAnnotation = MKPointAnnotation()
        rocketAnnotation.coordinate = rocketCoordinate
        rocketAnnotation.title = "Rocket"
        mapView.addAnnotation(rocketAnnotation)
        
        // Add path if available
        if pathCoordinates.count > 1 {
            let polyline = MKPolyline(coordinates: pathCoordinates, count: pathCoordinates.count)
            mapView.addOverlay(polyline)
        }
        
        // Add direction indicator if we have user location and rocket location
        if let userLocation = userLocation {
            // Add a line from user to rocket
            let directionLine = [userLocation, rocketCoordinate]
            let linePath = MKPolyline(coordinates: directionLine, count: 2)
            mapView.addOverlay(linePath)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                // Check if this polyline is our path or our direction indicator
                if polyline.pointCount > 2 {
                    // Regular path
                    renderer.strokeColor = .blue
                    renderer.lineWidth = 3
                } else {
                    // Direction indicator
                    renderer.strokeColor = .orange
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [4, 4] // Dashed line
                }
                
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil } // Let system handle user location blue dot
            
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
