import Foundation

enum ClipEaseStoragePathError: LocalizedError {
    case invalidAttachmentFileName(String)
    case attachmentPathOutsideDirectory(fileName: String, directory: String)
    case invalidAttachmentDirectory(String)
    case attachmentDirectoryOutsideRoot(directory: String, root: String)

    var errorDescription: String? {
        switch self {
        case .invalidAttachmentFileName(let fileName):
            "非法附件文件名：\(fileName)"
        case .attachmentPathOutsideDirectory(let fileName, let directory):
            "附件路径越界：\(fileName) 不在 \(directory) 内"
        case .invalidAttachmentDirectory(let directory):
            "非法附件目录：\(directory)"
        case .attachmentDirectoryOutsideRoot(let directory, let root):
            "附件目录越界：\(directory) 不在 \(root) 内"
        }
    }
}

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

    static func sqliteStoreURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("ClipEase.sqlite")
    }

    static func diagnosticsStoreURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("ClipEaseDiagnostics.sqlite")
    }

    static func imagesDirectory(fileManager: FileManager = .default) throws -> URL {
        try liveAttachmentDirectory(named: "Images", fileManager: fileManager)
    }

    static func imageFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try attachmentFileURL(
            fileName: fileName,
            in: imagesDirectory(fileManager: fileManager)
        )
    }

    static func thumbnailsDirectory(fileManager: FileManager = .default) throws -> URL {
        try liveAttachmentDirectory(named: "Thumbnails", fileManager: fileManager)
    }

    static func thumbnailFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try attachmentFileURL(
            fileName: fileName,
            in: thumbnailsDirectory(fileManager: fileManager)
        )
    }

    static func richTextsDirectory(fileManager: FileManager = .default) throws -> URL {
        try liveAttachmentDirectory(named: "RichTexts", fileManager: fileManager)
    }

    static func richTextFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try attachmentFileURL(
            fileName: fileName,
            in: richTextsDirectory(fileManager: fileManager)
        )
    }

    static func appIconsDirectory(fileManager: FileManager = .default) throws -> URL {
        try liveAttachmentDirectory(named: "AppIcons", fileManager: fileManager)
    }

    static func appIconFileURL(
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try attachmentFileURL(
            fileName: fileName,
            in: appIconsDirectory(fileManager: fileManager)
        )
    }

    static func validAttachmentBaseName(_ fileName: String) throws -> String {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFileName.isEmpty,
              trimmedFileName != ".",
              trimmedFileName != "..",
              trimmedFileName == fileName,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              (fileName as NSString).pathComponents == [fileName],
              URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              URLComponents(string: fileName)?.path == fileName else {
            throw ClipEaseStoragePathError.invalidAttachmentFileName(fileName)
        }

        return fileName
    }

    static func attachmentFileURL(fileName: String, in directoryURL: URL) throws -> URL {
        let baseName = try validAttachmentBaseName(fileName)
        let destinationURL = directoryURL.appendingPathComponent(baseName, isDirectory: false)
        try validateAttachmentURL(destinationURL, isInside: directoryURL, fileName: fileName)
        return destinationURL
    }

    static func validateAttachmentURL(_ fileURL: URL, isInside directoryURL: URL, fileName: String) throws {
        let resolvedFilePath = resolvedPath(fileURL)
        let resolvedDirectoryPath = resolvedPath(directoryURL)
        guard isPath(resolvedFilePath, insideDirectoryPath: resolvedDirectoryPath) else {
            throw ClipEaseStoragePathError.attachmentPathOutsideDirectory(
                fileName: fileName,
                directory: resolvedDirectoryPath
            )
        }
    }

    static func validateLiveAttachmentDirectory(
        _ directoryURL: URL,
        storageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let rootURL = try storageRootURL ?? applicationSupportDirectory(fileManager: fileManager)
        try validateAttachmentDirectoryExistsIfPresent(directoryURL, fileManager: fileManager)

        let resolvedDirectoryPath = resolvedPath(directoryURL)
        let resolvedRootPath = resolvedPath(rootURL)
        guard isPath(resolvedDirectoryPath, insideDirectoryPath: resolvedRootPath) else {
            throw ClipEaseStoragePathError.attachmentDirectoryOutsideRoot(
                directory: resolvedDirectoryPath,
                root: resolvedRootPath
            )
        }
    }

    private static func liveAttachmentDirectory(
        named directoryName: String,
        fileManager: FileManager
    ) throws -> URL {
        let storageRootURL = try applicationSupportDirectory(fileManager: fileManager)
        let directoryURL = storageRootURL.appendingPathComponent(directoryName, isDirectory: true)
        try validateLiveAttachmentDirectory(
            directoryURL,
            storageRootURL: storageRootURL,
            fileManager: fileManager
        )
        return directoryURL
    }

    private static func validateAttachmentDirectoryExistsIfPresent(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: directoryURL.path)) != nil {
            throw ClipEaseStoragePathError.invalidAttachmentDirectory(directoryURL.lastPathComponent)
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            return
        }

        guard isDirectory.boolValue else {
            throw ClipEaseStoragePathError.invalidAttachmentDirectory(directoryURL.lastPathComponent)
        }
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isPath(_ path: String, insideDirectoryPath directoryPath: String) -> Bool {
        path.hasPrefix(directoryPath + "/")
    }
}
