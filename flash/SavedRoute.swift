import CoreLocation
import Foundation
import SwiftData

enum SavedRouteError: LocalizedError {
    case invalidCoordinate
    case emptyName
    case insufficientPoints
    case tooManyWaypoints
    case unsupportedVersion(Int)
    case routeNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate: "A route location has invalid coordinates."
        case .emptyName: "Enter a name for this route."
        case .insufficientPoints: "A route needs at least two different locations."
        case .tooManyWaypoints: "A walking route can have up to 25 locations."
        case .unsupportedVersion: "This route was saved in an unsupported format."
        case .routeNotFound: "This route is no longer available."
        }
    }
}

struct RouteCoordinate: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw SavedRouteError.invalidCoordinate
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) throws {
        try self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private enum CodingKeys: String, CodingKey { case latitude, longitude }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(latitude: container.decode(Double.self, forKey: .latitude),
                      longitude: container.decode(Double.self, forKey: .longitude))
    }
}

struct RouteDraft: Equatable {
    var name: String
    var definition: RouteDefinition

    init(name: String, definition: RouteDefinition) {
        self.name = name
        self.definition = definition
    }
}

enum RouteDefinition: Codable, Equatable, Sendable {
    case walking(waypoints: [RouteCoordinate])
    case recorded(track: [RouteCoordinate])

    var points: [RouteCoordinate] {
        switch self {
        case .walking(let waypoints): waypoints
        case .recorded(let track): track
        }
    }

    var isWalking: Bool {
        if case .walking = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, points }
    private enum Kind: String, Codable { case walking, recorded }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let points = try container.decode([RouteCoordinate].self, forKey: .points)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .walking: self = .walking(waypoints: points)
        case .recorded: self = .recorded(track: points)
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isWalking ? Kind.walking : Kind.recorded, forKey: .kind)
        try container.encode(points, forKey: .points)
    }

    func validate() throws {
        guard Set(points).count >= 2 else { throw SavedRouteError.insufficientPoints }
        if isWalking && points.count > 25 { throw SavedRouteError.tooManyWaypoints }
    }
}

/// Only recorded GPS tracks have a persisted distance. Walking paths are recalculated.
enum SavedRouteSummary: Codable, Equatable {
    case walking(waypointCount: Int)
    case recorded(distanceMeters: Double)

    private enum CodingKeys: String, CodingKey { case kind, waypointCount, distanceMeters }
    private enum Kind: String, Codable { case walking, recorded }

    init(definition: RouteDefinition) throws {
        try definition.validate()
        switch definition {
        case .walking(let waypoints): self = .walking(waypointCount: waypoints.count)
        case .recorded(let track):
            let distance = zip(track, track.dropFirst()).reduce(0.0) { total, pair in
                total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                    .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
            }
            self = .recorded(distanceMeters: distance)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .walking:
            let count = try container.decode(Int.self, forKey: .waypointCount)
            guard (2...25).contains(count) else {
                throw DecodingError.dataCorruptedError(forKey: .waypointCount, in: container,
                                                       debugDescription: "Invalid waypoint count")
            }
            self = .walking(waypointCount: count)
        case .recorded:
            let distance = try container.decode(Double.self, forKey: .distanceMeters)
            guard distance.isFinite, distance >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .distanceMeters, in: container,
                                                       debugDescription: "Invalid recorded distance")
            }
            self = .recorded(distanceMeters: distance)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .walking(let count):
            try container.encode(Kind.walking, forKey: .kind)
            try container.encode(count, forKey: .waypointCount)
        case .recorded(let distance):
            try container.encode(Kind.recorded, forKey: .kind)
            try container.encode(distance, forKey: .distanceMeters)
        }
    }
}

/// Versioning applies to the stored payload, independently of the SwiftData schema.
private struct StoredRouteDefinition: Codable {
    let version: Int
    let definition: RouteDefinition
}

@Model
final class SavedRoute {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.externalStorage) private var definitionData: Data
    private var summaryData: Data? = nil

    init(name: String, definition: RouteDefinition) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SavedRouteError.emptyName }
        try definition.validate()
        self.id = UUID()
        self.name = name
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        self.definitionData = try Self.encode(definition)
        self.summaryData = try JSONEncoder().encode(SavedRouteSummary(definition: definition))
    }

    func definition() throws -> RouteDefinition {
        let stored = try JSONDecoder().decode(StoredRouteDefinition.self, from: definitionData)
        guard stored.version == 1 else { throw SavedRouteError.unsupportedVersion(stored.version) }
        try stored.definition.validate()
        return stored.definition
    }

    func summary() throws -> SavedRouteSummary {
        if let summaryData {
            return try JSONDecoder().decode(SavedRouteSummary.self, from: summaryData)
        }
        // Routes saved before summaries were introduced remain readable.
        return try SavedRouteSummary(definition: definition())
    }

    fileprivate static func encode(_ definition: RouteDefinition) throws -> Data {
        try JSONEncoder().encode(StoredRouteDefinition(version: 1, definition: definition))
    }

    fileprivate func replace(name: String, data: Data, summary: Data) {
        self.name = name
        definitionData = data
        summaryData = summary
        updatedAt = Date()
    }
}

@MainActor
final class SavedRouteStore {
    private let container: ModelContainer

    init(context: ModelContext) {
        container = context.container
    }

    /// A separate context gives each operation a transaction without committing or
    /// rolling back unrelated edits in the caller's context.
    @discardableResult
    func save(_ draft: RouteDraft, replacing route: SavedRoute? = nil) throws -> SavedRoute {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SavedRouteError.emptyName }
        try draft.definition.validate()
        let data = try SavedRoute.encode(draft.definition)
        let summary = try JSONEncoder().encode(SavedRouteSummary(definition: draft.definition))
        let context = makeContext()
        let saved: SavedRoute
        if let route {
            saved = try find(route.id, in: context)
            saved.replace(name: name, data: data, summary: summary)
        } else {
            saved = try SavedRoute(name: name, definition: draft.definition)
            context.insert(saved)
        }
        try context.save()
        return saved
    }

    func duplicate(_ route: SavedRoute) throws -> SavedRoute {
        try save(RouteDraft(name: route.name + " copy", definition: route.definition()))
    }

    func delete(_ route: SavedRoute) throws {
        let context = makeContext()
        context.delete(try find(route.id, in: context))
        try context.save()
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func find(_ id: UUID, in context: ModelContext) throws -> SavedRoute {
        var descriptor = FetchDescriptor<SavedRoute>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let route = try context.fetch(descriptor).first else {
            throw SavedRouteError.routeNotFound
        }
        return route
    }
}
