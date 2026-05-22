#!/usr/bin/env python3
import plistlib
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


CHECKS: list[tuple[str, list[str]]] = [
    ("smoke check", ["python3", "scripts/smoke_check.py"]),
    ("help and retention polish guard", ["python3", "scripts/verify_help_and_retention_polish.py"]),
    ("visible debug menu guard", ["python3", "scripts/verify_no_visible_debug_menu.py"]),
    ("history search performance guard", ["python3", "scripts/verify_history_search_performance_guards.py"]),
    ("history search benchmark", ["python3", "scripts/benchmark_history_search_performance.py"]),
    ("history window animation guard", ["python3", "scripts/verify_history_window_animation_performance.py"]),
    ("history window interaction toast guard", ["python3", "scripts/verify_history_window_interaction_toast.py"]),
    ("card click performance guard", ["python3", "scripts/verify_card_click_performance_guards.py"]),
    ("card drag visuals guard", ["python3", "scripts/verify_card_drag_visuals.py"]),
    ("preview performance guard", ["python3", "scripts/verify_preview_window_performance_guards.py"]),
    ("preview copy feedback guard", ["python3", "scripts/verify_preview_copy_feedback.py"]),
    ("sound feedback guard", ["python3", "scripts/verify_sound_feedback_guards.py"]),
    ("stage 9 file capture guard", ["python3", "scripts/verify_stage9_file_capture_first_batch.py"]),
    ("stage 9 file pasteboard guard", ["python3", "scripts/verify_stage9_file_pasteboard_first_batch.py"]),
    ("stage 9 file basic actions guard", ["python3", "scripts/verify_stage9_file_basic_actions.py"]),
    ("stage 9 file dragout guard", ["python3", "scripts/verify_stage9_file_dragout_first_batch.py"]),
    ("stage 9 file paste fallback guard", ["python3", "scripts/verify_stage9_file_paste_fallback.py"]),
    ("git whitespace check", ["git", "diff", "--check"]),
]


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def load_plist(path: Path) -> dict:
    if not path.is_file():
        fail(f"Missing plist: {path.relative_to(ROOT)}")
    with path.open("rb") as file:
        return plistlib.load(file)


def require_text(path: Path, markers: list[str]) -> None:
    if not path.is_file():
        fail(f"Missing file: {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            fail(f"{path.relative_to(ROOT)} missing marker: {marker}")


def check_versions() -> tuple[str, str]:
    source_info = load_plist(ROOT / "Resources/Info.plist")
    app_info = load_plist(ROOT / ".build/ClipEase.app/Contents/Info.plist")

    short_version = source_info.get("CFBundleShortVersionString", "")
    build_version = source_info.get("CFBundleVersion", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", short_version):
        fail(f"Invalid short version: {short_version}")
    if not re.fullmatch(r"\d{6}\.\d{4}", build_version):
        fail(f"Invalid build timestamp: {build_version}")

    app_short_version = app_info.get("CFBundleShortVersionString", "")
    app_build_version = app_info.get("CFBundleVersion", "")
    if app_short_version != short_version or app_build_version != build_version:
        fail(
            ".build/ClipEase.app version does not match Resources/Info.plist: "
            f"{app_short_version}({app_build_version}) != {short_version}({build_version})"
        )

    executable = ROOT / ".build/ClipEase.app/Contents/MacOS/ClipEase"
    if not executable.is_file():
        fail("Missing .build/ClipEase.app executable")
    if not executable.stat().st_mode & 0o111:
        fail(".build/ClipEase.app executable is not executable")

    return short_version, build_version


def check_release_docs(short_version: str, build_version: str) -> None:
    require_text(
        ROOT / "docs/RELEASE_NOTES.md",
        [
            "# 第二版发布说明",
            f"`{short_version} ({build_version})`",
            "第二版不包含 iCloud 同步",
            "python3 scripts/final_release_gate.py",
            "./scripts/build-dmg.sh",
        ],
    )
    require_text(
        ROOT / "docs/RELEASE_CANDIDATE_PROCESS.md",
        [
            "轻贴 ClipEase 第二版发布候选包",
            "python3 scripts/final_release_gate.py",
            "./scripts/build-dmg.sh",
            "不会重新编译、不会递增版本号",
        ],
    )
    require_text(
        ROOT / "docs/RELEASE_CANDIDATE_REPORT.md",
        [
            short_version,
            build_version,
        ],
    )


def run_check(label: str, command: list[str]) -> bool:
    print(f"\n==> {label}")
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode != 0:
        print(f"FAIL: {label} exited with {result.returncode}")
        return False
    print(f"OK: {label}")
    return True


def main() -> int:
    short_version, build_version = check_versions()
    print(f"Release candidate: {short_version} ({build_version})")
    check_release_docs(short_version, build_version)

    failed = [label for label, command in CHECKS if not run_check(label, command)]
    if failed:
        print("\nFinal release gate failed:")
        for label in failed:
            print(f"- {label}")
        return 1

    print("\nFinal release gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
