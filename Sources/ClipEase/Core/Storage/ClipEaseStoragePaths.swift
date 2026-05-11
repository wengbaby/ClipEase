import Foundation

enum ClipEaseStoragePaths {
    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("ClipEase", isDirectory: true)
    }

    static func historyFileURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("history.json")
    }

    static func imagesDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Images", isDirectory: true)
    }

    static func imageFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try imagesDirectory(fileManager: fileManager)
            .appendingPathComponent(fileName)
    }

    static func thumbnailsDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static func thumbnailFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try thumbnailsDirectory(fileManager: fileManager)
            .appendingPathComponent(fileName)
    }

    static func richTextsDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("RichTexts", isDirectory: true)
    }

    static func richTextFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try richTextsDirectory(fileManager: fileManager)
            .appendingPathComponent(fileName)
    }

    static func appIconsDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("AppIcons", isDirectory: true)
    }

    static func appIconFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try appIconsDirectory(fileManager: fileManager)
            .appendingPathComponent(fileName)
    }
}
