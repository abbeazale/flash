import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif
import CryptoKit

extension XCTestCase {
    @MainActor
    func assertSnapshot<V: View>(
        matching view: V,
        named name: String,
        size: CGSize,
        colorScheme: ColorScheme = .dark,
        scale: CGFloat = defaultSnapshotScale,
        record: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let snapshotData = try XCTUnwrap(renderSnapshot(view, size: size, colorScheme: colorScheme, scale: scale))
        let baselineURL = try snapshotURL(named: name, file: file)
        let fileManager = FileManager.default

        if record || !fileManager.fileExists(atPath: baselineURL.path) {
            try snapshotData.write(to: baselineURL, options: .atomic)
            if !record {
                XCTFail("Recorded new snapshot for \(name); rerun the test to validate.", file: file, line: line)
            }
            return
        }

        let baselineData = try Data(contentsOf: baselineURL)
        if baselineData.sha256Digest != snapshotData.sha256Digest {
            let failureURL = baselineURL.deletingLastPathComponent().appendingPathComponent("\(name)_failed.png")
            try? snapshotData.write(to: failureURL, options: .atomic)
            XCTFail("Snapshot mismatch for \(name). Saved diff at \(failureURL.lastPathComponent).", file: file, line: line)
        }
    }

    private func snapshotURL(named name: String, file: StaticString) throws -> URL {
        let fileURL = URL(fileURLWithPath: String(file))
        let directory = fileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(name).png")
    }

    @MainActor
    private func renderSnapshot<V: View>(
        _ view: V,
        size: CGSize,
        colorScheme: ColorScheme,
        scale: CGFloat
    ) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #elseif canImport(AppKit)
        return renderer.nsImage?.pngData()
        #else
        return nil
        #endif
    }
}

private let defaultSnapshotScale: CGFloat = {
    #if canImport(UIKit)
    return UIScreen.main.scale
    #else
    return 2
    #endif
}()

private extension Data {
    var sha256Digest: String {
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

#if canImport(AppKit)
private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
