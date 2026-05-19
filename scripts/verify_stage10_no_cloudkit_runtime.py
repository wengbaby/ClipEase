#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_PATHS = [
    ROOT / "Sources",
    ROOT / "Resources",
    ROOT / "Package.swift",
]
EXCLUDED_DIRS = {".build", ".git"}
ALLOWED_SYNC_WORDS = {
    "async",
    "saveAsync",
    "saveSync",
    "DispatchQueue.main.async",
    "syncLatestItemFocusIfNeeded",
    "syncRegistration",
    "synchronizeSelectedFileReference",
    "syncStyleStateFromSelection",
}


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def iter_files() -> list[Path]:
    files: list[Path] = []
    for path in SCAN_PATHS:
        if path.is_file():
            files.append(path)
            continue
        for candidate in path.rglob("*"):
            if any(part in EXCLUDED_DIRS for part in candidate.parts):
                continue
            if candidate.is_file() and candidate.suffix in {".swift", ".plist", ".entitlements", ".json"}:
                files.append(candidate)
    return files


def main() -> None:
    forbidden_exact = [
        "import CloudKit",
        "CKContainer",
        "CKDatabase",
        "CKRecord",
        "CKAsset",
        "NSUbiquitousKeyValueStore",
        "NSUbiquitousContainer",
        "com.apple.developer.icloud",
        "iCloud.com.",
        "CloudKitContainer",
    ]
    suspicious_sync_tokens = [
        "SyncService",
        "CloudSync",
        "ICloudSync",
        "RemoteSync",
        "syncEnabled",
        "syncStatus",
        "同步开关",
        "同步状态",
        "iCloud 同步",
    ]

    offenders: list[str] = []
    for path in iter_files():
        text = path.read_text(encoding="utf-8", errors="ignore")
        rel = path.relative_to(ROOT)
        for token in forbidden_exact:
            if token in text:
                offenders.append(f"{rel}: forbidden runtime token {token}")
        for token in suspicious_sync_tokens:
            if token in text and token not in ALLOWED_SYNC_WORDS:
                offenders.append(f"{rel}: suspicious sync runtime token {token}")

    if offenders:
        fail("Stage 10 must not add CloudKit/iCloud runtime:\n" + "\n".join(offenders))

    print("OK Stage 10 no CloudKit runtime checks passed")


if __name__ == "__main__":
    main()
