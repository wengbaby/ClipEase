#!/usr/bin/env python3
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

FORBIDDEN_PATTERNS = [
    "JSONClipboardHistoryRepository",
    "SQLiteHistoryMigration",
    "ClipboardHistoryMigrationResult",
    "repositoryKind",
    "ClipboardHistoryRepositoryKind",
    "is_favorite",
    "favorited_at",
    "migration_results",
    "retention_exempt",
    "isFavorite",
    "favoritedAt",
]

FORBIDDEN_GLOBS = [
    ".build/**",
    ".git/**",
    "dev-logs/**",
    "docs/**",
]

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

func sqliteCount(_ databaseURL: URL, _ sql: String) throws -> Int {
    let database = try SQLiteDatabase(url: databaseURL)
    defer { database.close() }
    return try database.queryInt(sql)
}

func sqliteStrings(_ databaseURL: URL, _ sql: String) throws -> [String] {
    let database = try SQLiteDatabase(url: databaseURL)
    defer { database.close() }
    return try database.query(sql).map { $0.requiredText("name") }
}

func makeItem(index: Int, groupID: ClipboardGroup.ID? = nil) -> ClipboardItem {
    let source = SourceAppInfo.clipease
    let createdAt = Date(timeIntervalSince1970: 1_779_000_000 - Double(index))
    return ClipboardItem(
        id: UUID(),
        type: .text,
        text: "SQLite baseline item \(index)",
        url: nil,
        linkTitle: nil,
        linkSubtitle: nil,
        imageFileName: nil,
        imageWidth: nil,
        imageHeight: nil,
        imageHash: nil,
        richTextFileName: nil,
        fileReferences: [],
        createdAt: createdAt,
        sourceAppName: source.name,
        sourceBundleID: source.bundleID,
        iconName: source.iconName,
        iconFileName: source.iconFileName,
        headerColorHex: source.headerColorHex,
        isPinned: index == 0,
        pinnedAt: index == 0 ? createdAt.addingTimeInterval(30) : nil,
        groupID: groupID,
        groupedAt: groupID == nil ? nil : createdAt.addingTimeInterval(60)
    )
}

func makeGroup() -> ClipboardGroup {
    let createdAt = Date(timeIntervalSince1970: 1_779_100_000)
    return ClipboardGroup(
        id: UUID(),
        name: "Baseline",
        colorHex: ClipboardGroup.defaultColors[0],
        iconName: ClipboardGroup.defaultIcons[0],
        sortOrder: 0,
        createdAt: createdAt,
        updatedAt: createdAt
    )
}

@main
enum VerifySQLiteOnlyBaseline {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clipease-sqlite-only-baseline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("ClipEase.sqlite")
        let group = makeGroup()
        let items = [
            makeItem(index: 0),
            makeItem(index: 1, groupID: group.id),
            makeItem(index: 2)
        ]
        let store = SQLiteClipboardStore(databaseURL: databaseURL)
        try store.replaceAllItems(with: items, groups: [group])

        let columns = try sqliteStrings(databaseURL, "PRAGMA table_info('clipboard_items')")
        let forbiddenColumns = ["is_favorite", "favorited_at", "retention_exempt"]
        for column in forbiddenColumns {
            try require(!columns.contains(column), "clipboard_items must not contain \(column)")
        }

        let tables = try sqliteStrings(databaseURL, "SELECT name FROM sqlite_master WHERE type = 'table'")
        try require(!tables.contains("migration_results"), "schema must not contain migration_results")

        let indexes = try sqliteStrings(databaseURL, "SELECT name FROM sqlite_master WHERE type = 'index'")
        try require(!indexes.contains("idx_clipboard_items_favorite"), "schema must not contain favorite index")

        let snapshot = try store.loadSnapshot()
        try require(snapshot.items.count == items.count, "loaded item count mismatch")
        try require(snapshot.groups.count == 1, "loaded group count mismatch")
        try require(snapshot.items.contains(where: { $0.groupID == group.id }), "group relationship missing")
        let groupItemCount = try sqliteCount(databaseURL, "SELECT COUNT(*) FROM group_items")
        try require(groupItemCount == 1, "group_items count mismatch")
        print("OK SQLite-only schema baseline verified")
    }
}
'''


def excluded(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    return any(rel.match(pattern) for pattern in FORBIDDEN_GLOBS)


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def verify_no_forbidden_text() -> None:
    offenders: list[str] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or excluded(path):
            continue
        if path.suffix not in {".swift", ".py"}:
            continue
        if path.name == "verify_sqlite_only_baseline.py":
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for pattern in FORBIDDEN_PATTERNS:
            if pattern in text:
                offenders.append(f"{path.relative_to(ROOT)}: {pattern}")

    if offenders:
        fail("forbidden SQLite-only baseline markers found:\n" + "\n".join(offenders))


def verify_migration_file_absent() -> None:
    migration_path = ROOT / "Sources/ClipEase/Core/Storage/SQLiteHistoryMigration.swift"
    if migration_path.exists():
        fail("SQLiteHistoryMigration.swift must be deleted or excluded from build")


def verify_package_has_no_explicit_migration_reference() -> None:
    package_text = (ROOT / "Package.swift").read_text(encoding="utf-8")
    if re.search(r"SQLiteHistoryMigration\.swift|SQLiteHistoryMigration", package_text):
        fail("Package.swift must not reference SQLiteHistoryMigration")


def run_harness() -> None:
    with tempfile.TemporaryDirectory(prefix="clipease-sqlite-only-harness-") as tmp:
        tmp_path = Path(tmp)
        harness_path = tmp_path / "VerifySQLiteOnlyBaseline.swift"
        binary_path = tmp_path / "verify-sqlite-only-baseline"
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
        ]
        subprocess.run(
            ["swiftc", *sources, str(harness_path), "-lsqlite3", "-o", str(binary_path)],
            cwd=ROOT,
            check=True,
        )
        subprocess.run([str(binary_path)], cwd=ROOT, check=True)


def main() -> None:
    verify_migration_file_absent()
    verify_package_has_no_explicit_migration_reference()
    verify_no_forbidden_text()
    run_harness()
    print("OK SQLite-only data baseline checks passed")


if __name__ == "__main__":
    main()
