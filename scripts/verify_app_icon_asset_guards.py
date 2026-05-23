#!/usr/bin/env python3
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_ICON = ROOT / "Resources/ClipEase.icns"


def run(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def main() -> None:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="clipease-icon-") as temp_dir:
        iconset = Path(temp_dir) / "ClipEase.iconset"
        run(["iconutil", "-c", "iconset", "-o", str(iconset), str(APP_ICON)])
        icon_1024 = iconset / "icon_512x512@2x.png"
        if not icon_1024.exists():
            failures.append("Resources/ClipEase.icns must include icon_512x512@2x.png")
        else:
            alpha_bounds = run([
                "magick",
                str(icon_1024),
                "-alpha",
                "extract",
                "-format",
                "%@",
                "info:",
            ])
            width, height, offset_x, offset_y = parse_geometry(alpha_bounds)
            if width >= 900 or height >= 900:
                failures.append(
                    f"1024 icon alpha bounds are too large ({alpha_bounds}); keep macOS safe margins"
                )
            if offset_x < 50 or offset_y < 50:
                failures.append(
                    f"1024 icon alpha bounds start too close to the canvas edge ({alpha_bounds})"
                )

            alpha_colors = int(run([
                "magick",
                str(icon_1024),
                "-alpha",
                "extract",
                "-format",
                "%k",
                "info:",
            ]))
            if alpha_colors <= 2:
                failures.append("1024 icon alpha channel must be antialiased, not 1-bit")

    if failures:
        print("App icon asset guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK app icon has safe margins and antialiased rounded edges")


def parse_geometry(geometry: str) -> tuple[int, int, int, int]:
    size, x_offset, y_offset = geometry.replace("+", " ", 2).split(" ", 2)
    width, height = size.split("x", 1)
    return int(width), int(height), int(x_offset), int(y_offset)


if __name__ == "__main__":
    main()
