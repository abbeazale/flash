//
//  MapView.swift
//  flash
//
//  Created by abbe on 2024-05-22.
//

import Foundation
import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    var route: [CLLocation]
    @Binding var region: MKCoordinateRegion
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
            // Remove existing overlays
            uiView.removeOverlays(uiView.overlays)
            
            // Update the route
            updateRoute(uiView)
            
            // Set the region only if it has changed significantly
            if shouldUpdateRegion(currentRegion: uiView.region, newRegion: region) {
                uiView.setRegion(region, animated: true)
            }
        }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateRoute(_ mapView: MKMapView) {
            guard !route.isEmpty else { return }
            
            let coordinates = route.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
            
            // Fit the map to show the entire route
            let rect = polyline.boundingMapRect
            mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50), animated: true)
        }
        
        private func shouldUpdateRegion(currentRegion: MKCoordinateRegion, newRegion: MKCoordinateRegion) -> Bool {
            let latDiff = abs(currentRegion.center.latitude - newRegion.center.latitude)
            let lonDiff = abs(currentRegion.center.longitude - newRegion.center.longitude)
            let spanLatDiff = abs(currentRegion.span.latitudeDelta - newRegion.span.latitudeDelta)
            let spanLonDiff = abs(currentRegion.span.longitudeDelta - newRegion.span.longitudeDelta)
            
            // Update if the difference is significant (you can adjust these thresholds)
            return latDiff > 0.01 || lonDiff > 0.01 || spanLatDiff > 0.01 || spanLonDiff > 0.01
        }
    
    
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
