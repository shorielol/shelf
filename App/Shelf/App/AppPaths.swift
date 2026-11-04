import Foundation

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "Shelf", directoryHint: .isDirectory)
    }

    static var layout: URL { support.appending(path: "layout.json") }
    static var backups: URL { support.appending(path: "Backups", directoryHint: .isDirectory) }
}
