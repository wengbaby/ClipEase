#!/usr/bin/env python3
"""Create deterministic synthetic ClipEase fixtures without user clipboard data."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import struct
import subprocess
import tempfile
import uuid
import zlib
from pathlib import Path
from typing import Any


FIXTURE_SCHEMA = "ClipEasePerformanceFixture/v2"
RECORD_FIXTURES = (
    ("S1K", 1_000, "startupText"),
    ("T10K", 10_000, "dailyMixed"),
    ("M100K", 100_000, "permanentMixed"),
)
ASSET_FIXTURE = ("A3K", 3_000, "mixedAssets")
ASSET_SUFFIXES = (".png", ".heic", ".pdf", ".rtf", ".txt")
UUID_NAMESPACE = uuid.UUID("f564d995-fdb1-4315-b7be-76ca59f61d7c")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    files = sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    for path in files:
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(path.stat().st_size.to_bytes(8, "big"))
        digest.update(bytes.fromhex(file_sha256(path)))
    return digest.hexdigest()


def fixture_size(root: Path) -> int:
    return sum(path.stat().st_size for path in root.rglob("*") if path.is_file())


def deterministic_item(identifier: str, index: int, kind: str) -> dict[str, Any]:
    item_types = ("text", "link", "color", "file", "image", "richText")
    item_type = "text" if kind == "startupText" else item_types[index % len(item_types)]
    return {
        "id": str(uuid.uuid5(UUID_NAMESPACE, f"{identifier}:{index}")),
        "type": item_type,
        "plainText": f"{identifier} ClipEase deterministic performance item {index}",
        "sourceBundleID": f"com.clipease.fixture.source{index % 17:02d}",
        "createdAt": 1_700_000_000 + index,
        "updatedAt": 1_700_000_000 + index,
        "isPinned": index % 997 == 0,
        "searchToken": f"token-{index % 211:03d}",
    }


def create_record_fixture(
    root: Path,
    identifier: str,
    count: int,
    kind: str,
) -> dict[str, Any]:
    fixture_root = root / identifier
    fixture_root.mkdir(parents=True, exist_ok=True)
    records_path = fixture_root / "items.jsonl"
    with records_path.open("w", encoding="utf-8", newline="\n") as stream:
        for index in range(count):
            stream.write(
                json.dumps(
                    deterministic_item(identifier, index, kind),
                    ensure_ascii=False,
                    separators=(",", ":"),
                    sort_keys=True,
                )
                + "\n"
            )
    return {
        "id": identifier,
        "kind": kind,
        "itemCount": count,
        "schema": FIXTURE_SCHEMA,
        "relativePath": identifier,
        "fileCount": 1,
        "payloadByteCount": fixture_size(fixture_root),
        "treeSHA256": tree_sha256(fixture_root),
    }


def png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(chunk_type + payload) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(payload))
        + chunk_type
        + payload
        + struct.pack(">I", checksum)
    )


def deterministic_png(width: int = 16, height: int = 16) -> bytes:
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(
                (
                    (x * 17) % 256,
                    (y * 17) % 256,
                    ((x + y) * 11) % 256,
                    255,
                )
            )
        rows.append(bytes(row))
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(b"".join(rows), level=9))
        + png_chunk(b"IEND", b"")
    )


def deterministic_solid_png(width: int, height: int) -> bytes:
    if width <= 0 or height <= 0:
        raise ValueError("PNG dimensions must be positive")
    compressor = zlib.compressobj(level=9)
    compressed = bytearray()
    row = bytes([0]) + bytes((46, 140, 255, 255)) * width
    for _ in range(height):
        compressed.extend(compressor.compress(row))
    compressed.extend(compressor.flush())
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", bytes(compressed))
        + png_chunk(b"IEND", b"")
    )


def deterministic_burst_png(minimum_size: int = 8 * 1024 * 1024) -> bytes:
    base = deterministic_png(width=64, height=64)
    iend = png_chunk(b"IEND", b"")
    if not base.endswith(iend):
        raise RuntimeError("deterministic PNG seed is missing IEND")
    payload_size = max(1, minimum_size - len(base) - 12)
    payload = (b"ClipEase-A3K-Burst-" * ((payload_size // 19) + 1))[:payload_size]
    return base[:-len(iend)] + png_chunk(b"ceAs", payload) + iend


def deterministic_pdf(page_count: int = 1) -> bytes:
    if page_count <= 0:
        raise ValueError("PDF page count must be positive")
    page_ids = list(range(3, 3 + page_count))
    content_ids = list(range(3 + page_count, 3 + page_count * 2))
    kids = " ".join(f"{identifier} 0 R" for identifier in page_ids)
    objects: list[bytes] = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{kids}] /Count {page_count} >>".encode(),
    ]
    objects.extend(
        (
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] "
            f"/Contents {content_id} 0 R >>"
        ).encode()
        for content_id in content_ids
    )
    content = b"q\nQ\n"
    objects.extend(
        b"<< /Length 4 >>\nstream\n" + content + b"endstream"
        for _ in content_ids
    )
    result = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, value in enumerate(objects, start=1):
        offsets.append(len(result))
        result.extend(f"{index} 0 obj\n".encode())
        result.extend(value)
        result.extend(b"\nendobj\n")
    xref_offset = len(result)
    result.extend(f"xref\n0 {len(objects) + 1}\n".encode())
    result.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        result.extend(f"{offset:010d} 00000 n \n".encode())
    result.extend(
        (
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_offset}\n%%EOF\n"
        ).encode()
    )
    return bytes(result)


def heic_seed_from_png(png: bytes) -> bytes:
    with tempfile.TemporaryDirectory(prefix="clipease-heic-seed-") as directory:
        root = Path(directory)
        source = root / "seed.png"
        destination = root / "seed.heic"
        source.write_bytes(png)
        result = subprocess.run(
            [
                "/usr/bin/sips",
                "-s",
                "format",
                "heic",
                str(source),
                "--out",
                str(destination),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not destination.is_file():
            raise RuntimeError(
                "unable to create deterministic HEIC seed with sips: "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return destination.read_bytes()


def create_asset_fixture(
    root: Path,
    count: int,
    *,
    include_stress_assets: bool | None = None,
) -> dict[str, Any]:
    fixture_root = root / ASSET_FIXTURE[0]
    asset_root = fixture_root / "assets"
    asset_root.mkdir(parents=True, exist_ok=True)

    png = deterministic_png()
    if include_stress_assets is None:
        include_stress_assets = count == ASSET_FIXTURE[1]
    seed_by_suffix = {
        ".png": png,
        ".heic": heic_seed_from_png(png),
        ".pdf": deterministic_pdf(),
        ".rtf": b"{\\rtf1\\ansi\\deff0 ClipEase A3K deterministic rich text.}\n",
        ".txt": b"ClipEase A3K deterministic file payload.\n",
    }
    burst_png = deterministic_burst_png() if include_stress_assets else None
    large_png = (
        deterministic_solid_png(width=8_192, height=4_096)
        if include_stress_assets
        else None
    )
    limit_pdf = deterministic_pdf(page_count=25) if include_stress_assets else None
    references_path = fixture_root / "assets.jsonl"
    with references_path.open("w", encoding="utf-8", newline="\n") as stream:
        for index in range(count):
            profile: str | None = None
            pixel_width: int | None = None
            pixel_height: int | None = None
            page_count: int | None = None
            if include_stress_assets and index < 30:
                suffix = ".png"
                seed = burst_png
                profile = "burst8MiB"
                pixel_width = 64
                pixel_height = 64
            elif include_stress_assets and index == 30:
                suffix = ".png"
                seed = large_png
                profile = "image32MP"
                pixel_width = 8_192
                pixel_height = 4_096
            elif include_stress_assets and index == 31:
                suffix = ".pdf"
                seed = limit_pdf
                profile = "pdf25Pages"
                page_count = 25
            else:
                suffix = ASSET_SUFFIXES[index % len(ASSET_SUFFIXES)]
                seed = seed_by_suffix[suffix]
            kind = suffix.removeprefix(".")
            relative_path = Path("assets") / kind / f"{index:06d}{suffix}"
            destination = fixture_root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            if seed is None:
                raise RuntimeError(f"missing deterministic seed for {profile}")
            destination.write_bytes(seed)
            record = {
                "id": str(uuid.uuid5(UUID_NAMESPACE, f"A3K:{index}")),
                "kind": kind,
                "relativePath": relative_path.as_posix(),
                "byteCount": destination.stat().st_size,
                "sha256": file_sha256(destination),
            }
            if profile is not None:
                record["profile"] = profile
            if pixel_width is not None and pixel_height is not None:
                record["pixelWidth"] = pixel_width
                record["pixelHeight"] = pixel_height
            if page_count is not None:
                record["pageCount"] = page_count
            stream.write(
                json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n"
            )

    return {
        "id": ASSET_FIXTURE[0],
        "kind": ASSET_FIXTURE[2],
        "itemCount": count,
        "schema": FIXTURE_SCHEMA,
        "relativePath": ASSET_FIXTURE[0],
        "fileCount": count + 1,
        "payloadByteCount": fixture_size(fixture_root),
        "treeSHA256": tree_sha256(fixture_root),
        "assetKinds": [suffix.removeprefix(".") for suffix in ASSET_SUFFIXES],
        "stressProfiles": (
            {
                "burst8MiBCount": 30,
                "maximumImagePixels": 8_192 * 4_096,
                "maximumPDFPages": 25,
            }
            if include_stress_assets
            else None
        ),
    }


def create_new_payload_directory(path: Path) -> None:
    if path.exists():
        raise FileExistsError(
            f"payload directory must not already exist; refusing to replace {path}"
        )
    path.mkdir(parents=True)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--payload-directory", required=True, type=Path)
    parser.add_argument(
        "--asset-count",
        type=int,
        default=ASSET_FIXTURE[1],
        help="test-only override; production runner must use the default 3000",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    if args.asset_count <= 0:
        raise SystemExit("--asset-count must be positive")
    create_new_payload_directory(args.payload_directory)

    fixtures = [
        create_record_fixture(args.payload_directory, identifier, count, kind)
        for identifier, count, kind in RECORD_FIXTURES
    ]
    fixtures.append(create_asset_fixture(args.payload_directory, args.asset_count))
    manifest = {
        "schemaVersion": 2,
        "fixtureSchema": FIXTURE_SCHEMA,
        "fixtures": fixtures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
