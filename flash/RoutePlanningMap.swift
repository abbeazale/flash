import MapKit
import SwiftUI

/// Camera changes are explicit so adding or dragging points never fights a user's pan.
struct RoutePlanningMap: UIViewRepresentable {
    let points: [RouteCoordinate]
    let paths: [[RouteCoordinate]]
    let allowsEditing: Bool
    @Binding var selectedPoint: Int?
    let focus: RouteMapFocus?
    let fitRequest: Int
    let onAdd: (CLLocationCoordinate2D) -> Void
    let onMove: (Int, CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.accessibilityIdentifier = "routes.planner.map"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.addPoint(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.lastPoints != points || coordinator.lastEditing != allowsEditing {
            coordinator.lastPoints = points
            coordinator.lastEditing = allowsEditing
            map.removeAnnotations(map.annotations)
            let indices = allowsEditing ? Array(points.indices) : (points.isEmpty ? [] : [0, points.count - 1])
            for index in indices {
                map.addAnnotation(WaypointAnnotation(index: index, coordinate: points[index].coordinate))
            }
        }
        if coordinator.lastPaths != paths {
            coordinator.lastPaths = paths
            map.removeOverlays(map.overlays)
            for path in paths where path.count >= 2 {
                let coordinates = path.map(\.coordinate)
                map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            }
        }
        if let focus, coordinator.lastFocus != focus.id {
            coordinator.lastFocus = focus.id
            map.setRegion(MKCoordinateRegion(center: focus.coordinate,
                                            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)), animated: true)
        }
        if coordinator.lastFit != fitRequest {
            coordinator.lastFit = fitRequest
            let coordinates = (paths.isEmpty ? points : paths.flatMap { $0 }).map(\.coordinate)
            if coordinates.count == 1, let coordinate = coordinates.first {
                map.setRegion(MKCoordinateRegion(center: coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)), animated: true)
            } else if coordinates.count > 1 {
                let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
                map.setVisibleMapRect(line.boundingMapRect,
                                      edgePadding: UIEdgeInsets(top: 65, left: 45, bottom: 45, right: 65), animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class WaypointAnnotation: NSObject, MKAnnotation {
        let index: Int
        @objc dynamic var coordinate: CLLocationCoordinate2D
        var title: String? { "Point \(index + 1)" }

        init(index: Int, coordinate: CLLocationCoordinate2D) {
            self.index = index
            self.coordinate = coordinate
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: RoutePlanningMap
        weak var map: MKMapView?
        var lastPoints: [RouteCoordinate] = []
        var lastPaths: [[RouteCoordinate]] = []
        var lastEditing = true
        var lastFit: Int?
        var lastFocus: UUID?

        init(_ parent: RoutePlanningMap) { self.parent = parent }

        @objc func addPoint(_ gesture: UITapGestureRecognizer) {
            guard parent.allowsEditing, let map else { return }
            parent.onAdd(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.allowsEditing else { return false }
            var view = touch.view
            while let current = view {
                if current is MKAnnotationView || current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? WaypointAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: point, reuseIdentifier: nil)
            view.glyphText = parent.allowsEditing ? "\(point.index + 1)" : (point.index == 0 ? "S" : "F")
            view.markerTintColor = point.index == 0 ? .systemGreen : .systemIndigo
            view.isDraggable = parent.allowsEditing
            view.canShowCallout = false
            view.displayPriority = .required
            view.accessibilityLabel = "Waypoint \(point.index + 1)"
            view.accessibilityIdentifier = "routes.planner.point.\(point.index)"
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard parent.allowsEditing, let point = view.annotation as? WaypointAnnotation else { return }
            DispatchQueue.main.async { self.parent.selectedPoint = point.index }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let point = view.annotation as? WaypointAnnotation else { return }
            DispatchQueue.main.async {
                if self.parent.selectedPoint == point.index { self.parent.selectedPoint = nil }
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting:
                view.setDragState(.dragging, animated: true)
            case .ending:
                if let point = view.annotation as? WaypointAnnotation {
                    parent.onMove(point.index, point.coordinate)
                }
                view.setDragState(.none, animated: true)
            case .canceling:
                if let point = view.annotation as? WaypointAnnotation,
                   parent.points.indices.contains(point.index) {
                    point.coordinate = parent.points[point.index].coordinate
                }
                view.setDragState(.none, animated: true)
            case .none, .dragging:
                break
            @unknown default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            return renderer
        }
    }
}
