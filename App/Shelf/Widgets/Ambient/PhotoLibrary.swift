import CoreGraphics
import Foundation
import ImageIO
import os

/// A decoded, downsampled photo ready to draw.
nonisolated struct FramedPhoto: @unchecked Sendable, Equatable {
    let url: URL
    let image: CGImage
    let date: Date?

    static func == (lhs: FramedPhoto, rhs: FramedPhoto) -> Bool { lhs.url == rhs.url && lhs.image === rhs.image }
}

/// Finds and decodes images off the main actor. Thumbnails come straight from ImageIO,
/// so a 40-megapixel HEIC never gets decoded at full size.
nonisolated enum PhotoLibrary {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    static let maxPhotos = 200
    /// Stop looking after this many entries, so a huge folder tree can't stall the scan.
    static let maxEntriesScanned = 20_000
    private static let logger = Logger(subsystem: "app.shelf", category: "photos")

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath)
    }

    /// Image files in `folder` and its subfolders (packages such as a Photos library are skipped), shuffled.
    @concurrent static func imageURLs(in folder: String) async -> [URL] {
        let root = expand(folder)
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                logger.debug("Skipping \(url.path, privacy: .private): \(error.localizedDescription)")
                return true
            }
        ) else { return [] }

        var found: [URL] = []
        var scanned = 0
        while let url = enumerator.nextObject() as? URL, found.count < maxPhotos, scanned < maxEntriesScanned {
            scanned += 1
            if Task.isCancelled { return [] }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            found.append(url)
        }
        return found.shuffled()
    }

    /// A thumbnail no larger than `maxPixel` on its long side, orientation applied.
    @concurrent static func thumbnail(for url: URL, maxPixel: Int) async -> FramedPhoto? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            logger.debug("Can't open \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return FramedPhoto(url: url, image: image, date: captureDate(source: source, url: url))
    }

    /// EXIF capture date when there is one, otherwise the file's modification date.
    private static func captureDate(source: CGImageSource, url: URL) -> Date? {
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = exifFormatter.date(from: stamp) {
            return date
        }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static let exifFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}
