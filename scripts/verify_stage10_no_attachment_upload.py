#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = [
    ROOT / "Sources/ClipEase",
    ROOT / "Package.swift",
    ROOT / "Resources",
]


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def iter_files() -> list[Path]:
    files: list[Path] = []
    for root in SCAN_ROOTS:
        if root.is_file():
            files.append(root)
            continue
        for path in root.rglob("*"):
            if path.is_file() and path.suffix in {".swift", ".plist", ".entitlements", ".json"}:
                files.append(path)
    return files


def main() -> None:
    forbidden_tokens = [
        "CKAsset",
        "CloudKit",
        "NSUbiquitous",
        "ubiquity",
        "iCloudDrive",
        "iCloud Drive",
        "uploadAttachment",
        "downloadAttachment",
        "remoteAsset",
        "remote_asset",
        "assetUpload",
        "assetDownload",
        "copyItemToICloud",
        "uploadFile",
        "downloadFile",
    ]

    offenders: list[str] = []
    for path in iter_files():
        text = path.read_text(encoding="utf-8", errors="ignore")
        rel = path.relative_to(ROOT)
        for token in forbidden_tokens:
            if token in text:
                offenders.append(f"{rel}: {token}")

    if offenders:
        fail("Stage 10 must not add attachment upload/download runtime:\n" + "\n".join(offenders))

    print("OK Stage 10 no attachment upload checks passed")


if __name__ == "__main__":
    main()
