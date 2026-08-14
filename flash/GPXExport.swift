import CoreLocation
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum GPXExportError: LocalizedError, Equatable {
    case emptyRoute
    case invalidCoordinate(index: Int)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyRoute:
            "This run does not have a route to export."
        case .invalidCoordinate:
            "The route contains a location that cannot be exported."
        case .encodingFailed:
            "Flash could not encode this run as GPX."
        }
    }
}

enum GPXExporter {
    static func makeGPX(
        route: [CLLocation],
        heartRate: [HeartRateDataPoint],
        name: String
    ) throws -> String {
        guard !route.isEmpty else {
            throw GPXExportError.emptyRoute
        }

        let sortedRoute = route.sorted { $0.timestamp < $1.timestamp }
        for (index, location) in sortedRoute.enumerated() {
            let coordinate = location.coordinate
            guard coordinate.latitude.isFinite,
                  coordinate.longitude.isFinite,
                  (-90.0...90.0).contains(coordinate.latitude),
                  coordinate.longitude >= -180.0,
                  coordinate.longitude < 180.0 else {
                throw GPXExportError.invalidCoordinate(index: index)
            }
        }

        let validHeartRates = heartRate
            .compactMap { point -> ValidHeartRate? in
                guard point.heartRate.isFinite else { return nil }
                let roundedValue = Int(point.heartRate.rounded())
                guard (1...255).contains(roundedValue) else { return nil }
                return ValidHeartRate(timestamp: point.timestamp, value: roundedValue)
            }
            .sorted { $0.timestamp < $1.timestamp }
        let timestampFormatter = makeTimestampFormatter()

        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Flash" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">"#,
            "  <trk>",
            "    <name>\(escapeXML(name))</name>",
            "    <trkseg>"
        ]

        for location in sortedRoute {
            let coordinate = location.coordinate
            lines.append(
                "      <trkpt lat=\"\(decimal(coordinate.latitude, places: 8))\" lon=\"\(decimal(coordinate.longitude, places: 8))\">"
            )

            if location.altitude.isFinite {
                lines.append("        <ele>\(decimal(location.altitude, places: 2))</ele>")
            }
            lines.append("        <time>\(timestampFormatter.string(from: location.timestamp))</time>")

            if let nearest = nearestHeartRate(to: location.timestamp, in: validHeartRates) {
                lines.append("        <extensions>")
                lines.append("          <gpxtpx:TrackPointExtension>")
                lines.append("            <gpxtpx:hr>\(nearest.value)</gpxtpx:hr>")
                lines.append("          </gpxtpx:TrackPointExtension>")
                lines.append("        </extensions>")
            }

            lines.append("      </trkpt>")
        }

        lines.append(contentsOf: [
            "    </trkseg>",
            "  </trk>",
            "</gpx>"
        ])

        return lines.joined(separator: "\n") + "\n"
    }

    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Flash-Run-\(formatter.string(from: date)).gpx"
    }

    private struct ValidHeartRate {
        let timestamp: Date
        let value: Int
    }

    private static func nearestHeartRate(
        to timestamp: Date,
        in samples: [ValidHeartRate]
    ) -> ValidHeartRate? {
        guard !samples.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = samples.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if samples[middle].timestamp < timestamp {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        if lowerBound == 0 { return samples[0] }
        if lowerBound == samples.count { return samples[samples.count - 1] }

        let before = samples[lowerBound - 1]
        let after = samples[lowerBound]
        let beforeDistance = abs(timestamp.timeIntervalSince(before.timestamp))
        let afterDistance = abs(after.timestamp.timeIntervalSince(timestamp))
        return beforeDistance <= afterDistance ? before : after
    }

    private static func decimal(_ value: Double, places: Int) -> String {
        String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            places,
            value
        )
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

extension UTType {
    static let gpx = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
}

struct GPXDocument: Transferable {
    let data: Data
    let filename: String

    init(route: [CLLocation], heartRate: [HeartRateDataPoint], name: String, date: Date) throws {
        let xml = try GPXExporter.makeGPX(route: route, heartRate: heartRate, name: name)
        guard let data = xml.data(using: .utf8) else {
            throw GPXExportError.encodingFailed
        }
        self.data = data
        self.filename = GPXExporter.filename(for: date)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { document in
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
