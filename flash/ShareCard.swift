import CoreTransferable
import Foundation
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ShareCardError: LocalizedError {
    case renderingFailed

    var errorDescription: String? {
        "Flash could not render the run card."
    }
}

struct ShareCardDocument: Transferable {
    let data: Data
    let filename: String

    var previewImage: UIImage? {
        UIImage(data: data)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { document in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent(document.filename)
            try document.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

struct ShareCardView: View {
    let run: RunningData
    let unitPresentation: RunUnitPresentation
    let mapImage: UIImage?

    var body: some View {
        ZStack {
            Color.flashBackground

            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.12),
                                Color.flashBackground.opacity(0.18),
                                Color.flashBackground.opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                statsOnlyBackground
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("FLASH")
                        .font(Font.custom("CallingCode-Regular", size: 26))
                        .tracking(3)
                    Spacer()
                    Text(run.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(Font.custom("CallingCode-Regular", size: 14))
                }

                Spacer()

                Text("RUN")
                    .font(Font.custom("CallingCode-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(2)

                Text(unitPresentation.distanceText(fromMeters: run.distance))
                    .font(Font.custom("CallingCode-Regular", size: 48))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                HStack(spacing: 24) {
                    stat(
                        title: "TIME",
                        value: RunUnitPresentation.durationText(run.duration)
                    )
                    stat(
                        title: "PACE",
                        value: unitPresentation.paceText(
                            fromMinutesPerKilometer: paceMinutesPerKilometer
                        )
                    )
                    if run.heartRate.isFinite, run.heartRate > 0 {
                        stat(
                            title: "AVG HR",
                            value: "\(Int(run.heartRate.rounded())) bpm"
                        )
                    }
                }
                .padding(.top, 18)
            }
            .padding(28)
        }
        .foregroundStyle(.white)
        .frame(width: 360, height: 450)
        .clipped()
    }

    private var statsOnlyBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.flashBackground, Color.black.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 34)
                .frame(width: 310, height: 310)
                .offset(x: 130, y: -150)

            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 20)
                .frame(width: 220, height: 220)
                .offset(x: -160, y: 190)
        }
    }

    private var paceMinutesPerKilometer: Double {
        guard run.distance.isFinite,
              run.duration.isFinite,
              run.distance > 0,
              run.duration > 0 else {
            return 0
        }
        return (run.duration / 60) / (run.distance / 1_000)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Font.custom("CallingCode-Regular", size: 11))
                .foregroundStyle(.white.opacity(0.62))
                .tracking(1)
            Text(value)
                .font(Font.custom("CallingCode-Regular", size: 16))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
    }
}

enum ShareCardRenderer {
    @MainActor
    static func makeDocument(
        run: RunningData,
        unitPresentation: RunUnitPresentation
    ) async throws -> ShareCardDocument {
        let mapImage = await RouteSnapshotRenderer.image(
            for: run.route,
            size: CGSize(width: 360, height: 450)
        )
        let card = ShareCardView(
            run: run,
            unitPresentation: unitPresentation,
            mapImage: mapImage
        )
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage,
              let data = image.pngData() else {
            throw ShareCardError.renderingFailed
        }

        return ShareCardDocument(
            data: data,
            filename: filename(for: run.date)
        )
    }

    private static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Flash-Run-\(formatter.string(from: date)).png"
    }
}

@MainActor
private enum RouteSnapshotRenderer {
    static func image(for route: [CLLocation], size: CGSize) async -> UIImage? {
        let validRoute = route
            .filter {
                let coordinate = $0.coordinate
                return CLLocationCoordinate2DIsValid(coordinate)
                    && coordinate.latitude.isFinite
                    && coordinate.longitude.isFinite
            }
            .sorted { $0.timestamp < $1.timestamp }
        guard !validRoute.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.mapType = .mutedStandard
        options.size = size
        options.scale = 3
        options.mapRect = paddedMapRect(for: validRoute)

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, error in
                guard error == nil, let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: draw(route: validRoute, on: snapshot))
            }
        }
    }

    private static func paddedMapRect(for route: [CLLocation]) -> MKMapRect {
        var mapRect = MKMapRect.null
        for location in route {
            let point = MKMapPoint(location.coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            mapRect = mapRect.union(pointRect)
        }

        let horizontalPadding = max(mapRect.size.width * 0.18, 1_200)
        let verticalPadding = max(mapRect.size.height * 0.18, 1_200)
        return mapRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private static func draw(
        route: [CLLocation],
        on snapshot: MKMapSnapshotter.Snapshot
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (index, location) in route.enumerated() {
                let point = snapshot.point(for: location.coordinate)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            context.cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            context.cgContext.setLineWidth(10)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()

            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(6)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()

            if route.count == 1, let location = route.first {
                let point = snapshot.point(for: location.coordinate)
                let markerRect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fillEllipse(in: markerRect)
            }
        }
    }
}
