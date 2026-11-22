import MapKit
import SwiftData
import SwiftUI

struct RoutePlannerView: View {
    let route: SavedRoute?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [RunnerProfile]
    @StateObject private var preview = RoutePreviewModel()
    @State private var draft = RouteDraft(name: "", definition: .walking(waypoints: []))
    @State private var initialDraft: RouteDraft?
    @State private var undoHistory: [[RouteCoordinate]] = []
    @State private var selectedPoint: Int?
    @State private var showingSearch = false
    @State private var confirmingDiscard = false
    @State private var errorMessage: String?
    @State private var loadFailed = false
    @State private var focus: RouteMapFocus?
    @State private var fitRequest = 0

    init(route: SavedRoute? = nil) { self.route = route }

    private var points: [RouteCoordinate] { draft.definition.points }
    private var isWalking: Bool { draft.definition.isWalking }
    private var hasChanges: Bool { initialDraft.map { $0 != draft } ?? false }
    private var units: RunUnitPresentation {
        RunUnitPresentation(unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit ?? .kilometers)
    }
    private var canSave: Bool {
        !loadFailed && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Set(points).count >= 2
    }
    private var paths: [[RouteCoordinate]] {
        if !isWalking { return [points] }
        if case .ready(let preview) = preview.state { return preview.legs.map(\.coordinates) }
        return []
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if loadFailed {
                        ContentUnavailableView("Route unavailable", systemImage: "exclamationmark.triangle",
                                               description: Text("Close this screen and try opening the route again."))
                    } else {
                        ZStack(alignment: .topTrailing) {
                            RoutePlanningMap(points: points, paths: paths, allowsEditing: isWalking,
                                             selectedPoint: $selectedPoint, focus: focus, fitRequest: fitRequest,
                                             onAdd: addPoint, onMove: movePoint)
                                .accessibilityIdentifier("routes.planner.map")
                            VStack(spacing: 12) {
                                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                                    .accessibilityLabel("Search for a place")
                                    .accessibilityIdentifier("routes.planner.search")
                                Button { fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                                    .disabled(points.isEmpty)
                                    .accessibilityLabel("Show entire route")
                            }
                            .font(.title3)
                            .buttonStyle(.borderedProminent)
                            .tint(Color.flashBackground)
                            .padding(12)
                        }
                        .frame(height: max(80, geometry.size.height * 0.52))
                        ScrollView { editorControls }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .background(Color.flashBackground)
            .foregroundStyle(.white)
            .navigationTitle(route == nil ? "Create route" : "Edit route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.flashBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("routes.planner.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("routes.planner.save")
                }
            }
            .sheet(isPresented: $showingSearch) {
                RoutePlaceSearch { coordinate in
                    focus = RouteMapFocus(coordinate: coordinate)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Couldn't update route", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .interactiveDismissDisabled(hasChanges)
            .onAppear(perform: load)
            .onChange(of: draft.definition) { _, definition in
                if case .walking(let waypoints) = definition { preview.update(waypoints: waypoints) }
            }
            .onDisappear { preview.cancel() }
        }
        .preferredColorScheme(.dark)
    }

    private var editorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Route name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("routes.planner.name")
            if isWalking {
                HStack {
                    Text("\(points.count) / 25 waypoints")
                        .accessibilityIdentifier("routes.planner.count")
                    Spacer()
                    if case .ready(let path) = preview.state {
                        Text(units.distanceText(fromMeters: path.distanceMeters)).bold()
                            .accessibilityIdentifier("routes.planner.distance")
                    }
                }
                .font(.subheadline)
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                        .disabled(undoHistory.isEmpty)
                        .accessibilityIdentifier("routes.planner.undo")
                    Spacer()
                    if let selectedPoint, points.indices.contains(selectedPoint) {
                        Button("Remove \(selectedPoint + 1)", systemImage: "trash") {
                            var changed = points
                            changed.remove(at: selectedPoint)
                            changePoints(changed)
                        }
                        .accessibilityIdentifier("routes.planner.remove")
                    } else {
                        Button("Close loop", systemImage: "arrow.triangle.2.circlepath") {
                            if let first = points.first { changePoints(points + [first]) }
                        }
                        .disabled(points.count < 2 || points.count >= 25 || points.first == points.last)
                        .accessibilityIdentifier("routes.planner.loop")
                    }
                }
                .buttonStyle(.bordered)
                Text(points.isEmpty ? "Search for an area, then tap the map to add your start." : "Tap to add a point. Touch and hold a pin to move it.")
                    .font(.footnote)
                previewStatus
                Text("Your waypoints are saved on this device. Walking paths refresh online and may change.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Recorded path · \(units.distanceText(fromMeters: trackDistance))")
                Text("This copy keeps the original GPS path. You can change its name.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding()
    }

    @ViewBuilder private var previewStatus: some View {
        switch preview.state {
        case .empty:
            Text("Add at least two different points to save a route.")
                .font(.caption)
        case .loading:
            HStack { ProgressView(); Text("Finding walking paths…") }.font(.footnote)
        case .ready:
            EmptyView()
        case .failed(let message):
            HStack(alignment: .top) {
                Text(message + " You can still save your waypoints.").font(.caption)
                Button("Retry") { preview.update(waypoints: points) }
                    .accessibilityIdentifier("routes.planner.retry")
            }
        }
    }

    private var trackDistance: Double {
        zip(points, points.dropFirst()).reduce(0) { sum, pair in
            sum + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
    }

    private func load() {
        guard !loadFailed else { return }
        if initialDraft != nil {
            if isWalking { preview.update(waypoints: points) }
            return
        }
        do {
            if let route { draft = RouteDraft(name: route.name, definition: try route.definition()) }
            initialDraft = draft
            if isWalking { preview.update(waypoints: points) }
            fitRequest += 1
        } catch {
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    private func addPoint(_ coordinate: CLLocationCoordinate2D) {
        guard isWalking else { return }
        guard points.count < 25 else {
            errorMessage = "A route can have up to 25 waypoints. Move or remove a point to adjust it."
            return
        }
        do { changePoints(points + [try RouteCoordinate(coordinate)]) }
        catch { errorMessage = error.localizedDescription }
    }

    private func movePoint(_ index: Int, _ coordinate: CLLocationCoordinate2D) {
        guard isWalking, points.indices.contains(index) else { return }
        do {
            var changed = points
            changed[index] = try RouteCoordinate(coordinate)
            changePoints(changed)
        } catch { errorMessage = error.localizedDescription }
    }

    private func changePoints(_ changed: [RouteCoordinate]) {
        guard changed != points else { return }
        undoHistory.append(points)
        if undoHistory.count > 50 { undoHistory.removeFirst() }
        selectedPoint = nil
        draft.definition = .walking(waypoints: changed)
    }

    private func undo() {
        guard let previous = undoHistory.popLast() else { return }
        selectedPoint = nil
        draft.definition = .walking(waypoints: previous)
    }

    private func save() {
        do {
            try SavedRouteStore(context: modelContext).save(draft, replacing: route)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct RouteMapFocus {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

private struct RoutePlaceSearch: View {
    let onSelect: (CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var message: String?
    @State private var searching = false
    @State private var request: MKLocalSearch?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                TextField("City, park, or address", text: $query)
                    .submitLabel(.search)
                    .onSubmit(search)
                    .accessibilityIdentifier("routes.search.query")
                Button("Search", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("routes.search.submit")
                if searching { ProgressView("Searching…") }
                if let message { Text(message).foregroundStyle(.secondary) }
                ForEach(results.indices, id: \.self) { index in
                    Button {
                        onSelect(results[index].placemark.coordinate)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(results[index].name ?? "Place")
                            Text(results[index].placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Find an area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onDisappear { searchTask?.cancel(); request?.cancel() }
        }
    }

    private func search() {
        searchTask?.cancel()
        request?.cancel()
        results = []
        message = nil
        searching = true
        let queryRequest = MKLocalSearch.Request()
        queryRequest.naturalLanguageQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = MKLocalSearch(request: queryRequest)
        request = search
        searchTask = Task { @MainActor in
            do {
                let response = try await search.start()
                guard !Task.isCancelled else { return }
                results = response.mapItems
                message = results.isEmpty ? "No places found. Try another search." : nil
            } catch {
                guard !Task.isCancelled else { return }
                message = "Search is unavailable. Check your connection and try again."
            }
            searching = false
        }
    }
}
