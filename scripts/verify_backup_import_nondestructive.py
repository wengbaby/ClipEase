#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_SERVICE_PATH = ROOT / "Sources/ClipEase/Core/Utilities/HistoryExportService.swift"


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


service_text = EXPORT_SERVICE_PATH.read_text(encoding="utf-8")
import_body = function_body(
    service_text,
    "private static func importSQLiteBackup(from backupURL: URL, sqliteURL: URL) throws -> BackupImportResult",
)
copy_body = function_body(
    service_text,
    "private static func copySQLiteBackupFiles(from sourceURL: URL, to destinationURL: URL) throws",
)

require(
    "SQLiteClipboardStore(databaseURL: sqliteURL)" not in import_body,
    "backup import does not construct SQLiteClipboardStore with the user-selected backup sqlite",
)
require(
    "temporaryDirectory" in import_body
    and "temporarySQLiteURL" in import_body
    and "copySQLiteBackupFiles(from: sqliteURL, to: temporarySQLiteURL)" in import_body,
    "backup import copies the sqlite backup into a temporary location before loading",
)
require(
    "validateBackupSchemaVersion(at: temporarySQLiteURL)" in import_body
    and "SQLiteClipboardStore(databaseURL: temporarySQLiteURL)" in import_body,
    "backup import validates and loads only the temporary sqlite copy",
)
require(
    "validateSQLiteBackupFileIsRegular(sourceURL)" in copy_body
    and "validateSQLiteBackupFileIsRegular(destinationURL)" in copy_body,
    "backup import validates the main sqlite file is regular before and after copying",
)
require(
    '"-wal"' in copy_body and '"-shm"' in copy_body,
    "backup import preserves SQLite WAL/SHM sidecars when making the temporary copy",
)
require(
    "validateSQLiteBackupFileIsRegular(sourceSidecarURL)" in copy_body
    and "validateSQLiteBackupFileIsRegular(destinationSidecarURL)" in copy_body,
    "backup import validates WAL/SHM sidecars are regular before and after copying",
)
require(
    "case incompatibleSQLiteBackupSchema(Int)" in service_text
    and "userVersion >= SQLiteClipboardStore.currentSchemaVersion" in service_text,
    "old incompatible backup schemas fail gracefully instead of being reset in place",
)
require(
    "case invalidSQLiteBackupFile(String)" in service_text
    and "attributesOfItem(atPath: url.path)" in service_text
    and ".typeRegular" in service_text,
    "invalid sqlite backup files fail before SQLite is opened",
)

print("OK backup import non-destructive checks passed")
