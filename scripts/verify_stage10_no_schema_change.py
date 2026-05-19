#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SQLITE_STORE = ROOT / "Sources/ClipEase/Core/Storage/SQLiteClipboardStore.swift"
ITEM_MODEL = ROOT / "Sources/ClipEase/Core/Models/ClipboardItem.swift"
GROUP_MODEL = ROOT / "Sources/ClipEase/Core/Models/ClipboardGroup.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def main() -> None:
    store = SQLITE_STORE.read_text(encoding="utf-8")
    item_model = ITEM_MODEL.read_text(encoding="utf-8")
    group_model = GROUP_MODEL.read_text(encoding="utf-8")
    combined_models = "\n".join([item_model, group_model])

    version_match = re.search(r"static let currentSchemaVersion = (\d+)", store)
    require(version_match is not None, "missing SQLite currentSchemaVersion")
    require(version_match.group(1) == "3", "Stage 10 preflight must not bump SQLite schema version")

    forbidden_schema_tokens = [
        "deleted_at",
        "deleted_device",
        "device_id",
        "origin_device",
        "remote_id",
        "record_id",
        "change_tag",
        "zone_id",
        "sync_state",
        "sync_version",
        "conflict_status",
        "encryption_key",
        "encryption_metadata",
        "attachment_manifest",
        "remote_asset",
        "upload_state",
    ]
    offenders = [token for token in forbidden_schema_tokens if token in store]
    if offenders:
        fail("Stage 10 preflight must not add sync schema tokens: " + ", ".join(offenders))

    forbidden_model_tokens = [
        "remoteID",
        "recordID",
        "changeTag",
        "syncState",
        "syncVersion",
        "conflictStatus",
        "deletedAt",
        "deviceID",
        "originDevice",
    ]
    model_offenders = [token for token in forbidden_model_tokens if token in combined_models]
    if model_offenders:
        fail("Stage 10 preflight must not add sync model fields: " + ", ".join(model_offenders))

    print("OK Stage 10 no schema change checks passed")


if __name__ == "__main__":
    main()
