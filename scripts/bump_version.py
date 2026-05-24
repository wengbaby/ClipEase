#!/usr/bin/env python3

import argparse
import plistlib
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INFO_PLIST = ROOT / "Resources" / "Info.plist"


def parse_version(value: str) -> tuple[int, int, int]:
    parts = value.split(".")
    if len(parts) != 3:
        raise ValueError(f"Expected semantic version like 0.1.0, got {value}")
    return tuple(int(part) for part in parts)


def format_version(major: int, minor: int, patch: int) -> str:
    return f"{major}.{minor}.{patch}"


def next_version(current: str, bump: str) -> str:
    major, minor, patch = parse_version(current)

    if bump == "none":
        return current
    if bump == "major":
        return format_version(major + 1, 0, 0)
    if bump == "minor":
        return format_version(major, minor + 1, 0)
    if bump == "patch":
        return format_version(major, minor, patch + 1)

    raise ValueError(f"Unsupported bump type: {bump}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Update ClipEase app version.")
    parser.add_argument(
        "--bump",
        choices=["none", "major", "minor", "patch"],
        default="none",
        help="Marketing version bump. CFBundleVersion timestamp is always updated.",
    )
    args = parser.parse_args()

    with INFO_PLIST.open("rb") as file:
        plist = plistlib.load(file)

    current_version = plist["CFBundleShortVersionString"]
    current_build = plist["CFBundleVersion"]

    plist["CFBundleShortVersionString"] = next_version(current_version, args.bump)
    plist["CFBundleVersion"] = datetime.now().strftime("%y%m%d.%H%M")

    with INFO_PLIST.open("wb") as file:
        plistlib.dump(plist, file, sort_keys=False)

    print(
        f"Version {current_version} ({current_build}) -> "
        f"{plist['CFBundleShortVersionString']} ({plist['CFBundleVersion']})"
    )


if __name__ == "__main__":
    main()
