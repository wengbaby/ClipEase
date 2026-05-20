#!/usr/bin/env python3
import html
import re
import subprocess
import sys
import zipfile
from pathlib import Path


def xml_texts(xml: str) -> list[str]:
    return [
        html.unescape(re.sub(r"<[^>]+>", "", match))
        for match in re.findall(r"<[^:>]*:?t(?:\s[^>]*)?>([\s\S]*?)</[^:>]*:?t>", xml)
    ]


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def verify_python_extraction(path: Path) -> str:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if path.suffix.lower() == ".xlsx":
            shared = []
            if "xl/sharedStrings.xml" in names:
                shared = [normalize(value) for value in xml_texts(archive.read("xl/sharedStrings.xml").decode("utf-8", "ignore"))]
            rows = []
            for name in sorted(n for n in names if n.startswith("xl/worksheets/sheet") and n.endswith(".xml")):
                xml = archive.read(name).decode("utf-8", "ignore")
                for row_xml in re.findall(r"<row(?:\s[^>]*)?>[\s\S]*?</row>", xml):
                    cells = []
                    for cell_xml in re.findall(r"<c(?:\s[^>]*)?>[\s\S]*?</c>", row_xml):
                        value_match = re.search(r"<[^:>]*:?v(?:\s[^>]*)?>([\s\S]*?)</[^:>]*:?v>", cell_xml)
                        if not value_match:
                            continue
                        value = html.unescape(re.sub(r"<[^>]+>", "", value_match.group(1)))
                        if (" t=\"s\"" in cell_xml or " t='s'" in cell_xml) and value.isdigit():
                            index = int(value)
                            if 0 <= index < len(shared):
                                value = shared[index]
                        value = normalize(value)
                        if value:
                            cells.append(value)
                    if cells:
                        rows.append("\t".join(cells))
            return "\n".join(rows)
        if path.suffix.lower() == ".docx" and "word/document.xml" in names:
            xml = archive.read("word/document.xml").decode("utf-8", "ignore")
            return "\n".join(normalize("".join(xml_texts(block))) for block in re.findall(r"<w:p(?:\s[^>]*)?>[\s\S]*?</w:p>", xml))
        if path.suffix.lower() == ".pptx":
            slides = []
            for name in sorted(n for n in names if n.startswith("ppt/slides/slide") and n.endswith(".xml")):
                text = "\n".join(normalize(value) for value in xml_texts(archive.read(name).decode("utf-8", "ignore")))
                if text.strip():
                    slides.append(text)
            return "\n\n".join(slides)
    return ""


def verify_unzip_does_not_block(path: Path) -> None:
    result = subprocess.run(
        ["/usr/bin/unzip", "-Z1", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
        check=True,
    )
    if not result.stdout:
        raise RuntimeError("unzip produced no entry list")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_office_preview_extraction.py <docx|xlsx|pptx>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"missing file: {path}", file=sys.stderr)
        return 2

    verify_unzip_does_not_block(path)
    text = verify_python_extraction(path)
    if not text.strip():
        print("FAIL: no selectable text extracted", file=sys.stderr)
        return 1

    print("PASS: extracted selectable text")
    print(text[:500])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
