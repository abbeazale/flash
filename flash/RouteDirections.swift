import CoreLocation
import MapKit

struct RoutePath: Equatable {
    let coordinates: [RouteCoordinate]
    let distanceMeters: Double
}

struct WalkingRoutePreview: Equatable {
    let legs: [RoutePath]
    var distanceMeters: Double { legs.reduce(0) { $0 + $1.distanceMeters } }
}

@MainActor
protocol WalkingRouteCalculating {
    func path(from start: RouteCoordinate, to end: RouteCoordinate) async throws -> RoutePath
    func cancel()
}

@MainActor
final class AppleWalkingDirections: WalkingRouteCalculating {
    private var currentRequest: MKDirections?

    func path(from start: RouteCoordinate, to end: RouteCoordinate) async throws -> RoutePath {
        if start == end { return RoutePath(coordinates: [start, end], distanceMeters: 0) }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        currentRequest = directions
        defer {
            if currentRequest === directions { currentRequest = nil }
        }
        let response = try await directions.calculate()
        try Task.checkCancellation()
        guard let route = response.routes.first,
              route.distance.isFinite, route.distance > 0,
              route.polyline.pointCount >= 2 else { throw RouteDirectionsError.noPath }
        let points = route.polyline.points()
        let coordinates = try (0..<route.polyline.pointCount).map {
            try RouteCoordinate(points[$0].coordinate)
        }
        return RoutePath(coordinates: coordinates, distanceMeters: route.distance)
    }

    func cancel() { currentRequest?.cancel() }
}

enum RouteDirectionsError: LocalizedError {
    case noPath

    var errorDescription: String? {
        "No walking path was found between these points. Try moving a point."
    }
}

/// A preview belongs to one open editor. Apple paths never enter the saved route model.
@MainActor
final class RoutePreviewModel: ObservableObject {
    enum State: Equatable {
        case empty
        case loading
        case ready(WalkingRoutePreview)
        case failed(String)
    }

    @Published private(set) var state: State = .empty
    private let calculator: any WalkingRouteCalculating
    private let debounceNanoseconds: UInt64
    private var task: Task<Void, Never>?
    private var revision = 0
    private var legs: [Leg: RoutePath] = [:]

    private struct Leg: Hashable {
        let start: RouteCoordinate
        let end: RouteCoordinate
    }

    init(calculator: (any WalkingRouteCalculating)? = nil,
         debounceNanoseconds: UInt64 = 350_000_000) {
        self.calculator = calculator ?? AppleWalkingDirections()
        self.debounceNanoseconds = debounceNanoseconds
    }

    func update(waypoints: [RouteCoordinate]) {
        cancel()
        guard waypoints.count >= 2 else {
            state = .empty
            return
        }
        state = .loading
        let requestedRevision = revision
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                var calculatedLegs: [RoutePath] = []
                for (start, end) in zip(waypoints, waypoints.dropFirst()) {
                    try Task.checkCancellation()
                    let key = Leg(start: start, end: end)
                    let path: RoutePath
                    if let cached = legs[key] {
                        path = cached
                    } else {
                        path = try await calculator.path(from: start, to: end)
                        try Task.checkCancellation()
                        guard revision == requestedRevision else { return }
                        if legs.count >= 64 { legs.removeAll() }
                        legs[key] = path
                    }
                    // Keep legs separate: Apple may snap a waypoint to different
                    // entrances. Joining their lines would invent a walkable link.
                    calculatedLegs.append(path)
                }
                guard revision == requestedRevision else { return }
                state = .ready(WalkingRoutePreview(legs: calculatedLegs))
            } catch {
                guard !Task.isCancelled, revision == requestedRevision else { return }
                if let routeError = error as? RouteDirectionsError {
                    state = .failed(routeError.localizedDescription)
                } else {
                    state = .failed("Walking directions are unavailable. Check your connection and try again.")
                }
            }
        }
    }

    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
        calculator.cancel()
        state = .empty
    }
}
