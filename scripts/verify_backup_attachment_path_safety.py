#!/usr/bin/env python3
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORAGE_PATHS_PATH = ROOT / "Sources/ClipEase/Core/Storage/ClipEaseStoragePaths.swift"
EXPORT_SERVICE_PATH = ROOT / "Sources/ClipEase/Core/Utilities/HistoryExportService.swift"
PERSISTENCE_PATH = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryPersistence.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)
    print(f"PASS: {message}")


def function_body(text: str, signature: str) -> str:
    start = text.find(signature)
    if start == -1:
        fail(f"missing function signature: {signature}")

    brace_start = text.find("{", start)
    if brace_start == -1:
        fail(f"missing function body for: {signature}")

    depth = 0
    for index in range(brace_start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace_start + 1:index]

    fail(f"unterminated function body for: {signature}")
    return ""


def run_storage_path_harness() -> None:
    harness_source = """
import Foundation

@main
struct Harness {
    static func main() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clipease-path-safety-harness", isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: tempDirectory)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let validNames = ["image.png", "rich-text.rtf", "thumb 1.png"]
        let invalidNames = [
            "",
            ".",
            "..",
            " ../evil.png",
            "../evil.png",
            "safe/evil.png",
            "safe\\\\evil.png",
            "file:///tmp/evil.png",
            "https://example.com/evil.png",
            "%2Ftmp.png",
            "foo%2Fbar.png",
            "foo?bar.png",
            "foo#bar.png",
            "foo.png/"
        ]

        for fileName in validNames {
            let url = try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: tempDirectory)
            guard url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == tempDirectory.resolvingSymlinksInPath().standardizedFileURL.path else {
                fatalError("valid attachment escaped directory: \\(fileName)")
            }
        }

        for fileName in invalidNames {
            do {
                _ = try ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: tempDirectory)
                fatalError("invalid attachment accepted: \\(fileName)")
            } catch ClipEaseStoragePathError.invalidAttachmentFileName {
                continue
            }
        }

        let realRoot = tempDirectory.appendingPathComponent("LiveRoot", isDirectory: true)
        let escapedRoot = tempDirectory.appendingPathComponent("EscapedRoot", isDirectory: true)
        try fileManager.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: escapedRoot, withIntermediateDirectories: true)

        let liveSymlink = realRoot.appendingPathComponent("Images", isDirectory: true)
        try fileManager.createSymbolicLink(at: liveSymlink, withDestinationURL: escapedRoot)
        do {
            try ClipEaseStoragePaths.validateLiveAttachmentDirectory(liveSymlink, storageRootURL: realRoot)
            fatalError("live symlink attachment directory accepted")
        } catch ClipEaseStoragePathError.invalidAttachmentDirectory {
        }

        let realImages = realRoot.appendingPathComponent("RealImages", isDirectory: true)
        try fileManager.createDirectory(at: realImages, withIntermediateDirectories: true)
        let escapedFile = escapedRoot.appendingPathComponent("image.png")
        fileManager.createFile(atPath: escapedFile.path, contents: Data())
        let symlinkedFile = realImages.appendingPathComponent("image.png")
        try fileManager.createSymbolicLink(at: symlinkedFile, withDestinationURL: escapedFile)
        do {
            try ClipEaseStoragePaths.validateAttachmentURL(symlinkedFile, isInside: realImages, fileName: "image.png")
            fatalError("symlinked attachment source escaped directory")
        } catch ClipEaseStoragePathError.attachmentPathOutsideDirectory {
        }
    }
}
"""
    with tempfile.TemporaryDirectory(prefix="clipease-path-safety-harness-") as tmp:
        tmp_path = Path(tmp)
        harness_path = tmp_path / "Harness.swift"
        binary_path = tmp_path / "verify-path-safety"
        harness_path.write_text(harness_source, encoding="utf-8")
        result = subprocess.run(
            [
                "swiftc",
                str(STORAGE_PATHS_PATH),
                str(harness_path),
                "-o",
                str(binary_path),
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if result.returncode != 0:
            print(result.stdout)
            fail("failed to compile attachment path safety harness")

        result = subprocess.run(
            [str(binary_path)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if result.returncode != 0:
            print(result.stdout)
            fail("attachment path safety harness failed")

    print("PASS: attachment basename helper rejects traversal and URL-like names at runtime")


storage_text = STORAGE_PATHS_PATH.read_text(encoding="utf-8")
export_text = EXPORT_SERVICE_PATH.read_text(encoding="utf-8")
persistence_text = PERSISTENCE_PATH.read_text(encoding="utf-8")

basename_body = function_body(
    storage_text,
    "static func validAttachmentBaseName(_ fileName: String) throws -> String",
)
attachment_url_body = function_body(
    storage_text,
    "static func attachmentFileURL(fileName: String, in directoryURL: URL) throws -> URL",
)
validate_url_body = function_body(
    storage_text,
    "static func validateAttachmentURL(_ fileURL: URL, isInside directoryURL: URL, fileName: String) throws",
)
restore_backup_body = function_body(
    export_text,
    "private static func restoreBackupAttachments(",
)
restore_attachment_body = function_body(
    export_text,
    "fileprivate static func restoreAttachment(",
)
copy_attachments_body = function_body(
    export_text,
    "private static func copyAttachments(",
)
delete_image_body = function_body(
    persistence_text,
    "func deleteImage(fileName: String)",
)
delete_rich_text_body = function_body(
    persistence_text,
    "func deleteRichText(fileName: String)",
)
delete_thumbnail_body = function_body(
    persistence_text,
    "func deleteThumbnail(fileName: String)",
)

require(
    'trimmedFileName.isEmpty' in basename_body
    and 'trimmedFileName != "."' in basename_body
    and 'trimmedFileName != ".."' in basename_body,
    "attachment basename rejects empty, dot, and dot-dot names",
)
require(
    '!fileName.contains("/")' in basename_body
    and '!fileName.contains("\\\\")' in basename_body
    and "(fileName as NSString).pathComponents == [fileName]" in basename_body,
    "attachment basename rejects slash, backslash, and path component names",
)
require(
    "URL(fileURLWithPath: fileName).lastPathComponent == fileName" in basename_body
    and "URLComponents(string: fileName)?.path == fileName" in basename_body,
    "attachment basename rejects URL/path names whose last component differs",
)
require(
    "validateAttachmentURL(destinationURL, isInside: directoryURL, fileName: fileName)" in attachment_url_body
    and ".resolvingSymlinksInPath().standardizedFileURL.path" in storage_text
    and "isPath(resolvedFilePath, insideDirectoryPath: resolvedDirectoryPath)" in validate_url_body,
    "attachment URL helper enforces symlink-resolved destination stays inside its directory",
)
require(
    "validateLiveAttachmentDirectory" in storage_text
    and "destinationOfSymbolicLink(atPath: directoryURL.path)" in storage_text
    and "attachmentDirectoryOutsideRoot" in storage_text
    and "liveAttachmentDirectory(named: \"Images\"" in storage_text
    and "liveAttachmentDirectory(named: \"Thumbnails\"" in storage_text
    and "liveAttachmentDirectory(named: \"RichTexts\"" in storage_text,
    "live image, thumbnail, and rich text directories reject symlinks and resolved root escapes",
)
require(
    "case invalidBackupAttachmentFileName(String)" in export_text
    and "case invalidBackupAttachmentPath(String)" in export_text,
    "backup import exposes clear invalid attachment errors",
)
require(
    "restoreBackupImageAttachment(" in restore_backup_body
    and "restoreBackupRichTextAttachment(" in restore_backup_body,
    "SQLite backup import restores image and rich text attachments through guarded helpers",
)
require(
    "sourceDirectoryURL" in restore_attachment_body
    and "destinationDirectoryURL" in restore_attachment_body
    and "validateAttachmentURL(sourceURL, isInside: sourceDirectoryURL, fileName: fileName)" in restore_attachment_body
    and "validateAttachmentURL(destinationURL, isInside: destinationDirectoryURL, fileName: fileName)" in restore_attachment_body,
    "backup attachment copy checks symlink-resolved source and destination directory boundaries",
)
require(
    "case invalidBackupAttachmentDirectory(String)" in export_text
    and "validateBackupAttachmentDirectory(backupImagesDirectory)" in export_text
    and "validateBackupAttachmentDirectory(backupRichTextsDirectory)" in export_text
    and "destinationOfSymbolicLink(atPath: directoryURL.path)" in export_text,
    "backup import rejects symlink or non-directory Images and RichTexts attachment directories",
)
require(
    "validateLiveAttachmentDirectory(liveImagesDirectory)" in export_text
    and "validateLiveAttachmentDirectory(liveRichTextsDirectory)" in export_text
    and "validateLiveAttachmentDirectory(destinationDirectoryURL)" in restore_attachment_body,
    "backup import verifies live attachment directories before writing",
)
require(
    "case invalidBackupAttachmentFile(String)" in export_text
    and "validateBackupAttachmentFileIsRegular(sourceURL, fileName: fileName)" in restore_attachment_body
    and "attributesOfItem(atPath: url.path)" in export_text
    and ".typeRegular" in export_text,
    "backup attachment copy rejects non-regular source files",
)
require(
    "ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: fromImagesDirectory)" in copy_attachments_body
    and "ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: toImagesDirectory)" in copy_attachments_body
    and "ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: fromRichTextsDirectory)" in copy_attachments_body
    and "ClipEaseStoragePaths.attachmentFileURL(fileName: fileName, in: toRichTextsDirectory)" in copy_attachments_body,
    "backup export copies image and rich text attachments through safe basename URLs",
)
require(
    "ClipEaseStoragePaths.imageFileURL(" in delete_image_body
    and "ClipEaseStoragePaths.thumbnailFileURL(" in delete_thumbnail_body
    and "ClipEaseStoragePaths.richTextFileURL(" in delete_rich_text_body,
    "image, thumbnail, and rich text deletion paths use guarded storage path helpers",
)

run_storage_path_harness()
print("OK backup attachment path safety checks passed")
