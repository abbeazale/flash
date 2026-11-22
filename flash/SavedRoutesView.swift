import CoreLocation
import SwiftData
import SwiftUI

struct SavedRoutesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRoute.updatedAt, order: .reverse) private var routes: [SavedRoute]
    @Query private var profiles: [RunnerProfile]
    @State private var creatingRoute = false
    @State private var selectedRoute: SavedRoute?
    @State private var routeToDelete: SavedRoute?
    @State private var errorMessage: String?

    private var units: RunUnitPresentation {
        RunUnitPresentation(unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit ?? .kilometers)
    }

    var body: some View {
        ZStack {
            Color.flashBackground.ignoresSafeArea()
            if let fetchError = _routes.fetchError {
                ContentUnavailableView {
                    Label("Routes unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(fetchError.localizedDescription)
                }
            } else if routes.isEmpty {
                ContentUnavailableView {
                    Label("No saved routes", systemImage: "map")
                } description: {
                    Text("Plan a walking route or save the path from a recorded run.")
                } actions: {
                    Button("Create route") { creatingRoute = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("routes.empty.create")
                }
            } else {
                List {
                    ForEach(routes) { route in
                        Button {
                            do {
                                _ = try route.definition()
                                selectedRoute = route
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(route.name).font(.headline)
                                    routeSummary(route)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                        }
                        .accessibilityIdentifier("routes.open.\(route.id.uuidString)")
                        .listRowBackground(Color.white.opacity(0.08))
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { routeToDelete = route }
                                .accessibilityIdentifier("routes.delete.\(route.id.uuidString)")
                            Button("Duplicate") { duplicate(route) }
                                .tint(.indigo)
                                .accessibilityIdentifier("routes.duplicate.\(route.id.uuidString)")
                        }
                        .contextMenu {
                            Button("Open", systemImage: "map") {
                                do {
                                    _ = try route.definition()
                                    selectedRoute = route
                                } catch { errorMessage = error.localizedDescription }
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(route) }
                            Button("Delete", systemImage: "trash", role: .destructive) { routeToDelete = route }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(.white)
        .navigationTitle("Routes")
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create route", systemImage: "plus") { creatingRoute = true }
                    .accessibilityIdentifier("routes.create")
            }
        }
        .sheet(isPresented: $creatingRoute) { RoutePlannerView() }
        .sheet(item: $selectedRoute) { RoutePlannerView(route: $0) }
        .confirmationDialog("Delete route?", isPresented: Binding(
            get: { routeToDelete != nil },
            set: { if !$0 { routeToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete route", role: .destructive) {
                guard let route = routeToDelete else { return }
                do { try SavedRouteStore(context: modelContext).delete(route) }
                catch { errorMessage = error.localizedDescription }
                routeToDelete = nil
            }
            Button("Cancel", role: .cancel) { routeToDelete = nil }
        } message: {
            Text("Delete \"\(routeToDelete?.name ?? "this route")\" from your saved routes?")
        }
        .alert("Couldn't update routes", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func routeSummary(_ route: SavedRoute) -> Text {
        do {
            switch try route.summary() {
            case .walking(let waypointCount):
                return Text("Walking plan · \(waypointCount) waypoints")
            case .recorded(let distanceMeters):
                return Text("Recorded run · \(units.distanceText(fromMeters: distanceMeters))")
            }
        } catch {
            return Text("Route unavailable: \(error.localizedDescription)")
        }
    }

    private func duplicate(_ route: SavedRoute) {
        do { _ = try SavedRouteStore(context: modelContext).duplicate(route) }
        catch { errorMessage = error.localizedDescription }
    }
}

struct SaveRunRouteSheet: View {
    let locations: [CLLocation]
    let suggestedName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [RunnerProfile]
    @State private var name: String
    @State private var errorMessage: String?

    init(locations: [CLLocation], suggestedName: String) {
        self.locations = locations
        self.suggestedName = suggestedName
        _name = State(initialValue: suggestedName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.flashBackground.ignoresSafeArea()
                Form {
                    Section("Route name") {
                        TextField("Name", text: $name)
                            .accessibilityIdentifier("routes.saveRun.name")
                    }
                    Section {
                        switch validatedTrack {
                        case .success(let track):
                            let units = RunUnitPresentation(unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit ?? .kilometers)
                            LabeledContent("Recorded distance", value: units.distanceText(fromMeters: recordedRouteDistance(track)))
                            Text("Saves a copy of this run's recorded path to your routes.")
                        case .failure(let error):
                            Label("This recorded path can't be saved.", systemImage: "exclamationmark.triangle")
                            Text(error.localizedDescription)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                }
                .scrollContentBackground(.hidden)
            }
            .foregroundStyle(.white)
            .navigationTitle("Save route")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("routes.saveRun.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canSaveTrack)
                        .accessibilityIdentifier("routes.saveRun.save")
                }
            }
            .alert("Couldn't save route", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private var validatedTrack: Result<[RouteCoordinate], Error> {
        Result {
            let track = try locations.map { try RouteCoordinate($0.coordinate) }
            guard Set(track).count >= 2 else { throw RecordedRouteError.insufficientPoints }
            return track
        }
    }

    private var canSaveTrack: Bool {
        if case .success = validatedTrack { return true }
        return false
    }

    private func save() {
        do {
            let track = try validatedTrack.get()
            try SavedRouteStore(context: modelContext).save(RouteDraft(name: name, definition: .recorded(track: track)))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private enum RecordedRouteError: LocalizedError {
    case insufficientPoints

    var errorDescription: String? {
        "The recorded path needs at least two distinct locations."
    }
}

private func recordedRouteDistance(_ track: [RouteCoordinate]) -> Double {
    zip(track, track.dropFirst()).reduce(0) { distance, pair in
        distance + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
    }
}
