//
//  MapView.swift
//  flash
//
//  Created by abbe on 2024-05-22.
//

import Foundation
import SwiftUI
import MapKit

/// Route polyline tagged with its role, so the renderer does not depend on overlay order.
final class RoutePolyline: MKPolyline {
    enum Kind {
        case base
        case highlight
    }

    var kind: Kind = .base
}

struct MapView: UIViewRepresentable {
    var route: [CLLocation]
    @Binding var region: MKCoordinateRegion
    /// Route indices to draw on top of the base route, e.g. one selected split.
    var highlightedRange: ClosedRange<Int>? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Rebuild the base route and fit the map only when the route itself changes. A split
        // selection must not reset the region the user is looking at.
        let signature = RouteSignature(route)
        if coordinator.routeSignature != signature {
            coordinator.routeSignature = signature
            coordinator.replaceBaseRoute(on: uiView, route: route)
        }

        let range = clampedRange()
        if coordinator.highlightedRange != range {
            coordinator.highlightedRange = range
            coordinator.replaceHighlight(on: uiView, route: route, range: range)
        }

        // Without a route, fall back to the bound region.
        if route.isEmpty, coordinator.shouldApply(region: region) {
            uiView.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func clampedRange() -> ClosedRange<Int>? {
        guard let highlightedRange, !route.isEmpty else { return nil }
        let lower = max(0, highlightedRange.lowerBound)
        let upper = min(route.count - 1, highlightedRange.upperBound)
        guard lower < upper else { return nil }
        return lower...upper
    }

    struct RouteSignature: Equatable {
        let count: Int
        let firstTimestamp: Date?
        let lastTimestamp: Date?

        init(_ route: [CLLocation]) {
            count = route.count
            firstTimestamp = route.first?.timestamp
            lastTimestamp = route.last?.timestamp
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        var routeSignature: RouteSignature?
        var highlightedRange: ClosedRange<Int>?
        private var baseOverlay: RoutePolyline?
        private var highlightOverlay: RoutePolyline?
        private var lastAppliedRegion: MKCoordinateRegion?

        init(_ parent: MapView) {
            self.parent = parent
        }

        func replaceBaseRoute(on mapView: MKMapView, route: [CLLocation]) {
            if let baseOverlay {
                mapView.removeOverlay(baseOverlay)
                self.baseOverlay = nil
            }
            guard !route.isEmpty else { return }

            var coordinates = route.map(\.coordinate)
            let polyline = RoutePolyline(coordinates: &coordinates, count: coordinates.count)
            polyline.kind = .base
            mapView.addOverlay(polyline, level: .aboveRoads)
            baseOverlay = polyline

            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
                edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50),
                animated: true
            )
        }

        func replaceHighlight(on mapView: MKMapView, route: [CLLocation], range: ClosedRange<Int>?) {
            if let highlightOverlay {
                mapView.removeOverlay(highlightOverlay)
                self.highlightOverlay = nil
            }
            guard let range else { return }

            var coordinates = route[range].map(\.coordinate)
            let polyline = RoutePolyline(coordinates: &coordinates, count: coordinates.count)
            polyline.kind = .highlight
            mapView.addOverlay(polyline, level: .aboveLabels)
            highlightOverlay = polyline
        }

        func shouldApply(region: MKCoordinateRegion) -> Bool {
            defer { lastAppliedRegion = region }
            guard let last = lastAppliedRegion else { return true }
            return abs(last.center.latitude - region.center.latitude) > 0.001
                || abs(last.center.longitude - region.center.longitude) > 0.001
                || abs(last.span.latitudeDelta - region.span.latitudeDelta) > 0.005
                || abs(last.span.longitudeDelta - region.span.longitudeDelta) > 0.005
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            let kind = (polyline as? RoutePolyline)?.kind ?? .base
            switch kind {
            case .base:
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
            case .highlight:
                renderer.strokeColor = .systemYellow
                renderer.lineWidth = 7
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
