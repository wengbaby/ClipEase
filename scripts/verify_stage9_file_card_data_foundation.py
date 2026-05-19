#!/usr/bin/env python3
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

MODEL = ROOT / "Sources/ClipEase/Core/Models/ClipboardItem.swift"
SQLITE_STORE = ROOT / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"
EXPORT_SERVICE = ROOT / "Sources/ClipEase/Core/Utilities/HistoryExportService.swift"
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"

HARNESS = r'''
import Foundation

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw VerificationFailure(description: message)
    }
}

func sqliteRows(_ databaseURL: URL, _ sql: String) throws -> [SQLiteRow] {
    let database = try SQLiteDatabase(url: databaseURL)
    defer { database.close() }
    return try database.query(sql)
}

func makeFileItem() -> ClipboardItem {
    let itemID = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_779_300_000)
    let files = [
        ClipboardFileReference(
            id: UUID(),
            itemID: itemID,
            orderIndex: 0,
            path: "/Users/name/Documents/alpha.txt",
            displayName: "alpha.txt",
            fileExtension: "txt",
            contentType: "public.plain-text",
            fileSize: 12,
            modifiedAt: createdAt.addingTimeInterval(-60),
            isDirectory: false,
            isAlias: false,
            pathStatus: .available,
            lastCheckedAt: createdAt,
            createdAt: createdAt
        ),
        ClipboardFileReference(
            id: UUID(),
            itemID: itemID,
            orderIndex: 1,
            path: "/Users/name/Desktop/Folder",
            displayName: "Folder",
            fileExtension: nil,
            contentType: "public.folder",
            fileSize: nil,
            modifiedAt: nil,
            isDirectory: true,
            isAlias: false,
            pathStatus: .unknown,
            lastCheckedAt: nil,
            createdAt: createdAt.addingTimeInterval(1)
        )
    ]

    return ClipboardItem(
        id: itemID,
        type: .file,
        text: "alpha.txt 等 2 个文件\n/Users/name/Documents/alpha.txt\n/Users/name/Desktop/Folder",
        url: nil,
        linkTitle: "alpha.txt",
        linkSubtitle: "/Users/name/Documents/alpha.txt",
        imageFileName: nil,
        imageWidth: nil,
        imageHeight: nil,
        imageHash: nil,
        richTextFileName: nil,
        fileReferences: files,
        createdAt: createdAt,
        sourceAppName: SourceAppInfo.clipease.name,
        sourceBundleID: SourceAppInfo.clipease.bundleID,
        iconName: SourceAppInfo.clipease.iconName,
        iconFileName: nil,
        headerColorHex: SourceAppInfo.clipease.headerColorHex,
        isPinned: false,
        pinnedAt: nil,
        groupID: nil,
        groupedAt: nil
    )
}

@main
enum VerifyStage9FileCardDataFoundation {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipease-stage9-file-data-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("ClipEase.sqlite")
        let store = SQLiteClipboardStore(databaseURL: databaseURL)
        let item = makeFileItem()
        try store.replaceAllItems(with: [item], groups: [])

        let tables = try sqliteRows(databaseURL, "SELECT name FROM sqlite_master WHERE type = 'table'")
            .map { $0.requiredText("name") }
        try require(tables.contains("clipboard_item_files"), "clipboard_item_files table missing")

        let version = try sqliteRows(databaseURL, "PRAGMA user_version").first?.requiredInt("user_version") ?? 0
        try require(version >= 3, "schema version must be at least 3")

        let fileRows = try sqliteRows(
            databaseURL,
            "SELECT file_path, file_name, display_order, is_directory, path_status FROM clipboard_item_files ORDER BY display_order"
        )
        try require(fileRows.count == 2, "file row count mismatch")
        try require(fileRows[0].requiredText("file_path") == "/Users/name/Documents/alpha.txt", "full file path not persisted")
        try require(fileRows[1].requiredBool("is_directory"), "directory flag not persisted")
        try require(fileRows[0].requiredText("path_status") == "available", "path status not persisted")

        let snapshot = try store.loadSnapshot()
        try require(snapshot.items.count == 1, "loaded item count mismatch")
        guard let loaded = snapshot.items.first else {
            throw VerificationFailure(description: "loaded item missing")
        }

        try require(loaded.type == .file, "file item type not restored")
        try require(loaded.fileReferences.map(\.path) == item.fileReferences.map(\.path), "file paths not restored")
        try require(loaded.text.contains("/Users/name/Documents/alpha.txt"), "plain text summary must include path for memory search")

        let backupURL = root.appendingPathComponent("Backup", isDirectory: true)
        try HistoryExportService.exportBackup(items: [item], groups: [], to: backupURL, includesAttachments: true)
        let backupStore = SQLiteClipboardStore(databaseURL: backupURL.appendingPathComponent("ClipEase.sqlite"))
        let backupSnapshot = try backupStore.loadSnapshot()
        try require(backupSnapshot.items.first?.fileReferences.first?.path == "/Users/name/Documents/alpha.txt",
                    "backup SQLite missing file path metadata")
        try require(!FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("alpha.txt").path),
                    "backup must not copy original file beside SQLite")

        try store.replaceAllItems(with: [], groups: [])
        let remainingFileRows = try sqliteRows(databaseURL, "SELECT COUNT(*) AS count FROM clipboard_item_files")
            .first?.requiredInt("count") ?? -1
        try require(remainingFileRows == 0, "file metadata rows should be removed with history")

        print("OK Stage 9 file card data foundation verified")
    }
}
'''


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def verify_static_guards() -> None:
    model_text = MODEL.read_text(encoding="utf-8")
    sqlite_text = SQLITE_STORE.read_text(encoding="utf-8")
    export_text = EXPORT_SERVICE.read_text(encoding="utf-8")
    store_text = STORE.read_text(encoding="utf-8")

    checks = {
        "file item type exists": "case file" in model_text,
        "file reference model exists": "struct ClipboardFileReference" in model_text,
        "no security scoped bookmark model": "bookmark" not in model_text.lower() + sqlite_text.lower(),
        "file metadata table exists": "CREATE TABLE IF NOT EXISTS clipboard_item_files" in sqlite_text,
        "full path column exists": "file_path TEXT NOT NULL" in sqlite_text,
        "display order column exists": "display_order INTEGER NOT NULL" in sqlite_text,
        "path status column exists": "path_status TEXT NOT NULL" in sqlite_text,
        "file table cascades on history delete": "REFERENCES clipboard_items(id) ON DELETE CASCADE" in sqlite_text,
        "no file path search index": "file_path)" not in sqlite_text and "file_name)" not in sqlite_text,
        "backup export carries file references": "fileReferences" in export_text,
        "backup export does not copy file references": "fileReferences" in export_text
        and "fileReferences.forEach" not in export_text
        and "copyAttachments" in export_text,
        "history external cleanup only handles app attachments": "compactMap(\\.imageFileName)" in store_text
        and "compactMap(\\.richTextFileName)" in store_text,
    }

    failures = [name for name, ok in checks.items() if not ok]
    if failures:
        fail("static guard failed:\n" + "\n".join(failures))

    forbidden_files = [
        ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift",
        ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift",
        ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift",
        ROOT / "Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift",
        ROOT / "Sources/ClipEase/Features/ClipboardMonitor/ClipboardMonitor.swift",
    ]
    for path in forbidden_files:
        if path.exists() and re.search(r"ClipboardFileReference|clipboard_item_files", path.read_text(encoding="utf-8")):
            fail(f"forbidden UI/capture/paste file references Stage 9 data foundation: {path.relative_to(ROOT)}")


def run_harness() -> None:
    with tempfile.TemporaryDirectory(prefix="clipease-stage9-file-data-harness-") as tmp:
        tmp_path = Path(tmp)
        harness_path = tmp_path / "VerifyStage9FileCardDataFoundation.swift"
        binary_path = tmp_path / "verify-stage9-file-card-data-foundation"
        harness_path.write_text(HARNESS, encoding="utf-8")
        sources = [
            "Sources/ClipEase/Core/Models/ClipboardItem.swift",
            "Sources/ClipEase/Core/Models/ClipboardGroup.swift",
            "Sources/ClipEase/Features/ClipboardMonitor/SourceAppInfo.swift",
            "Sources/ClipEase/Core/Utilities/Color+Hex.swift",
            "Sources/ClipEase/Core/Utilities/AppIconCache.swift",
            "Sources/ClipEase/Core/Storage/ClipEaseStoragePaths.swift",
            "Sources/ClipEase/Core/Storage/ClipboardHistoryRepository.swift",
            "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift",
            "Sources/ClipEase/Core/Utilities/HistoryExportService.swift",
        ]
        subprocess.run(
            ["swiftc", *sources, str(harness_path), "-lsqlite3", "-o", str(binary_path)],
            cwd=ROOT,
            check=True,
        )
        subprocess.run([str(binary_path)], cwd=ROOT, check=True)


def main() -> None:
    verify_static_guards()
    run_harness()
    print("OK Stage 9 file card data foundation checks passed")


if __name__ == "__main__":
    main()
