//
//  MapViews.swift
//  RocketTracker
//
//  Created by Gregory Wainer on 5/14/25.
//

import SwiftUI
import MapKit
import MapboxMaps

func getDeviceColor(for deviceID: UInt32) -> Color {
    let colors: [Color] = [.red, .blue, .green, .orange, .purple, .brown, .cyan]
    return colors[Int(deviceID) % colors.count]
}

func getUIDeviceColor(for deviceID: UInt32) -> UIColor {
    let colors: [UIColor] = [.red, .blue, .green, .orange, .purple, .brown, .cyan]
    return colors[Int(deviceID) % colors.count]
}

@MainActor
func mapView(for telemetry: TelemetryData, presenter: MainPresenter) -> some View {
    let mapConfig = MapConfig(
        center: CLLocationCoordinate2D(latitude: telemetry.lat, longitude: telemetry.lon),
        zoomLevel: 15,
        showsUserLocation: true // Always show user location regardless of tracking mode
    )
    
    return MapboxMapView(
        config: mapConfig, 
        presenter: presenter
    )
}

struct MapConfig {
    var center: CLLocationCoordinate2D
    var zoomLevel: Double
    var showsUserLocation: Bool = true
}

struct MapboxMapView: UIViewRepresentable {
    var config: MapConfig
    @ObservedObject var presenter: MainPresenter
    
    func makeUIView(context: Context) -> MapboxMaps.MapView {
        let options = MapInitOptions(
            mapOptions: MapOptions(
                constrainMode: .heightOnly,
                viewportMode: .default
            ),
            cameraOptions: CameraOptions(
                center: config.center, 
                zoom: config.zoomLevel
            )
        )
        
        let mapView = MapboxMaps.MapView(frame: .zero, mapInitOptions: options)
        
        // Always show location indicator (blue dot) regardless of tracking mode
        mapView.location.options.puckType = .puck2D()
        mapView.location.options.puckBearingEnabled = true
        
        // Important: This makes the user location show even when not tracking
        mapView.location.options.puckBearing = .heading
        
        return mapView
    }
    
    func updateUIView(_ uiView: MapboxMaps.MapView, context: Context) {
        // Update device paths, markers, etc.
    }
}

// Update mapView function to show all devices
// @MainActor
// func mapView(for telemetry: TelemetryData, presenter: MainPresenter) -> some View {
//     Group {
//         if #available(iOS 17.0, *) {
// //            let center = CLLocationCoordinate2D(latitude: 39.5, longitude: -98.0)
// //            Map(initialViewport: .camera(center: center, zoom: 2, bearing: 0, pitch: 0))
// //                .ignoresSafeArea()
//             Map(initialPosition: MapCameraPosition.region(presenter.mapRegion)) {
//                 // Add markers for each device
//                 ForEach(presenter.getAvailableDeviceIDs(), id: \.self) { deviceID in
//                     if let deviceTelemetry = presenter.getTelemetryData(for: deviceID) {
//                         let deviceColor = getDeviceColor(for: deviceID)
                        
//                         // Add marker for device position
//                         Marker("Device \(deviceID)", coordinate: CLLocationCoordinate2D(
//                             latitude: deviceTelemetry.lat,
//                             longitude: deviceTelemetry.lon
//                         ))
//                         .tint(deviceColor)
                        
//                         // Add path for device trail
//                         let devicePath = presenter.getPathCoordinates(for: deviceID)
//                         if devicePath.count > 1 {
//                             MapPolyline(coordinates: devicePath)
//                                 .stroke(deviceColor, lineWidth: 3)
//                         }
                        
//                         // Add direction line to this device if it's the selected one
//                         if presenter.selectedDeviceID == deviceID, let userLocation = presenter.userLocation {
//                             MapPolyline(coordinates: [userLocation, CLLocationCoordinate2D(
//                                 latitude: deviceTelemetry.lat,
//                                 longitude: deviceTelemetry.lon
//                             )])
//                             .stroke(deviceColor, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
//                         }
//                     }
//                 }

//                 // Add user location marker
//                 if presenter.userLocation != nil {
//                     UserAnnotation()
//                 }
//             }
//             .mapControls {
//                 MapCompass()
//                 MapUserLocationButton()
//             }
//             .mapStyle(.standard(elevation: .realistic))
//             .clipShape(RoundedRectangle(cornerRadius: 12))
//             .overlay(
//                 RoundedRectangle(cornerRadius: 12)
//                     .stroke(Color.gray.opacity(0.2), lineWidth: 1)
//             )
//             .padding(8)
//             .frame(height: 300)
//         } else {
//             // iOS 15-16 implementation with multi-device support
//             MultiDeviceMapView(presenter: presenter)
//                 .frame(height: 300)
//                 .edgesIgnoringSafeArea(.all)
//         }
//     }
// }

// iOS 15-16 MapView implementation
struct MultiDeviceMapView: UIViewRepresentable {
    var presenter: MainPresenter
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Clear existing annotations and overlays but keep user location
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        mapView.removeOverlays(mapView.overlays)
        
        // Get all device IDs
        let deviceIDs = presenter.getAvailableDeviceIDs()
        
        // Add annotations and overlays for each device with telemetry data
        var regionSet = false
        for deviceID in deviceIDs {
            if let telemetry = presenter.getTelemetryData(for: deviceID) {
                // Create annotation for this device
                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(
                    latitude: telemetry.lat,
                    longitude: telemetry.lon
                )
                annotation.title = "Device \(deviceID)"
                mapView.addAnnotation(annotation)
                
                // Add path for this device
                let path = presenter.getPathCoordinates(for: deviceID)
                if path.count > 1 {
                    let polyline = MKPolyline(coordinates: path, count: path.count)
                    polyline.title = "\(deviceID)" // Store device ID in title
                    mapView.addOverlay(polyline)
                }
                
                // If this is the selected device, center the map
                if deviceID == presenter.selectedDeviceID || (!regionSet && deviceIDs.count > 0) {
                    // Center on this device
                    let region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: telemetry.lat, longitude: telemetry.lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    mapView.setRegion(region, animated: true)
                    regionSet = true
                    
                    // Draw direction line from user to selected device
                    if let userLocation = presenter.userLocation {
                        let directionPoints = [userLocation, 
                                              CLLocationCoordinate2D(latitude: telemetry.lat, longitude: telemetry.lon)]
                        let directionLine = MKPolyline(coordinates: directionPoints, count: 2)
                        directionLine.title = "direction"
                        mapView.addOverlay(directionLine)
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MultiDeviceMapView
        
        init(_ parent: MultiDeviceMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                // Direction lines have title "direction"
                if polyline.title == "direction" {
                    renderer.strokeColor = .orange
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [4, 4]
                } else if let deviceIDString = polyline.title, let deviceID = UInt32(deviceIDString) {
                    // Device path - use device-specific color
                    renderer.strokeColor = getUIDeviceColor(for: deviceID)
                    renderer.lineWidth = 3
                } else {
                    // Default color
                    renderer.strokeColor = .blue
                    renderer.lineWidth = 3
                }
                
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil } // Let system handle user location
            
            let identifier = "DeviceMarker"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            // Extract device ID from title and set marker color
            if let title = annotation.title,
               let deviceIDString = title?.replacingOccurrences(of: "Device ", with: ""),
               let deviceID = UInt32(deviceIDString) {
                annotationView?.markerTintColor = getUIDeviceColor(for: deviceID)
                annotationView?.glyphImage = UIImage(systemName: "location.fill")
            } else {
                annotationView?.markerTintColor = .red
            }
            
            return annotationView
        }
    }
}

// Custom polyline with device ID information
class DevicePolyline: MKPolyline {
    var deviceID: UInt32 = 0
    var colorIndex: Int = 0
    var isDashed: Bool = false
}

// Custom annotation with device ID information
class DeviceAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var deviceID: UInt32
    var colorIndex: Int
    
    init(coordinate: CLLocationCoordinate2D, deviceID: UInt32, colorIndex: Int) {
        self.coordinate = coordinate
        self.deviceID = deviceID
        self.colorIndex = colorIndex
    }
    
    var title: String? {
        return "Device \(deviceID)"
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
    var presenter: MainPresenter
    var pathCoordinates: [CLLocationCoordinate2D]
    var userLocation: CLLocationCoordinate2D?
    var headingToRocket: Double?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Clear existing annotations and overlays but keep user location
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        mapView.removeOverlays(mapView.overlays)
        
        // Get all device IDs
        let deviceIDs = presenter.getAvailableDeviceIDs()
        
        // Add annotations and overlays for each device
        var regionSet = false
        for deviceID in deviceIDs {
            if let telemetry = presenter.getTelemetryData(for: deviceID) {
                // Create annotation for this device
                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(
                    latitude: telemetry.lat,
                    longitude: telemetry.lon
                )
                annotation.title = "Device \(deviceID)"
                mapView.addAnnotation(annotation)
                
                // Add path for this device
                let path = presenter.getPathCoordinates(for: deviceID)
                if path.count > 1 {
                    let polyline = MKPolyline(coordinates: path, count: path.count)
                    polyline.title = "\(deviceID)" // Store device ID in title for color lookup
                    mapView.addOverlay(polyline)
                }
                
                // If this is the selected device, set the region and add direction line
                if deviceID == presenter.selectedDeviceID || (!regionSet && !deviceIDs.isEmpty) {
                    // Set map region centered on this device
                    let region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: telemetry.lat, longitude: telemetry.lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    mapView.setRegion(region, animated: true)
                    regionSet = true
                    
                    // Add direction line from user to selected device
                    if let userLocation = presenter.userLocation {
                        let directionLine = [userLocation, CLLocationCoordinate2D(
                            latitude: telemetry.lat, 
                            longitude: telemetry.lon
                        )]
                        let linePath = MKPolyline(coordinates: directionLine, count: 2)
                        linePath.title = "direction"
                        mapView.addOverlay(linePath)
                    }
                }
            }
        }
        
        // Enable user location
        mapView.showsUserLocation = true
    }

    func getDeviceColor(for deviceID: UInt32) -> Color {
        let colors: [Color] = [.red, .blue, .green, .orange, .purple, .brown, .cyan]
        return colors[Int(deviceID) % colors.count]
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
