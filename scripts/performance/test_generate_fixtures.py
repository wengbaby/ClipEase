import importlib.util
import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "generate_fixtures",
    ROOT / "scripts/performance/generate_fixtures.py",
)
generate_fixtures = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(generate_fixtures)


class PerformanceFixtureGenerationTests(unittest.TestCase):
    def test_tree_hash_orders_files_by_posix_relative_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "assets/png").mkdir(parents=True)
            files = {
                "assets.jsonl": b"manifest\n",
                "assets/png/000000.png": b"image\n",
            }
            for relative_path, payload in files.items():
                (root / relative_path).write_bytes(payload)

            expected = hashlib.sha256()
            for relative_path in sorted(files):
                relative = relative_path.encode("utf-8")
                payload = files[relative_path]
                expected.update(len(relative).to_bytes(4, "big"))
                expected.update(relative)
                expected.update(len(payload).to_bytes(8, "big"))
                expected.update(hashlib.sha256(payload).digest())

            self.assertEqual(
                generate_fixtures.tree_sha256(root),
                expected.hexdigest(),
            )

    def test_record_fixtures_have_exact_counts_and_actual_tree_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = generate_fixtures.create_record_fixture(
                root=root,
                identifier="T10K",
                count=37,
                kind="mixed",
            )
            records = root / "T10K" / "items.jsonl"
            self.assertEqual(len(records.read_text().splitlines()), 37)
            self.assertEqual(fixture["treeSHA256"], generate_fixtures.tree_sha256(root / "T10K"))
            self.assertEqual(len(fixture["treeSHA256"]), 64)

            original_hash = fixture["treeSHA256"]
            records.write_text(records.read_text() + '{"changed":true}\n')
            self.assertNotEqual(original_hash, generate_fixtures.tree_sha256(root / "T10K"))

    def test_asset_fixture_contains_real_mixed_file_types_and_reference_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = generate_fixtures.create_asset_fixture(root=root, count=25)
            asset_root = root / "A3K"
            references = [
                json.loads(line)
                for line in (asset_root / "assets.jsonl").read_text().splitlines()
            ]
            self.assertEqual(len(references), 25)
            suffixes = {Path(reference["relativePath"]).suffix.lower() for reference in references}
            self.assertEqual(suffixes, {".png", ".heic", ".pdf", ".rtf", ".txt"})
            for reference in references:
                path = asset_root / reference["relativePath"]
                self.assertTrue(path.is_file())
                self.assertGreater(path.stat().st_size, 0)
                self.assertEqual(
                    reference["sha256"],
                    generate_fixtures.file_sha256(path),
                )
            self.assertEqual(fixture["treeSHA256"], generate_fixtures.tree_sha256(asset_root))

    def test_enterprise_stress_seeds_cover_burst_pixels_and_pdf_page_limit(self):
        burst = generate_fixtures.deterministic_burst_png()
        self.assertGreaterEqual(len(burst), 8 * 1024 * 1024)
        self.assertEqual(burst[:8], b"\x89PNG\r\n\x1a\n")

        large = generate_fixtures.deterministic_solid_png(8_192, 4_096)
        self.assertEqual(
            struct.unpack(">II", large[16:24]),
            (8_192, 4_096),
        )

        pdf = generate_fixtures.deterministic_pdf(page_count=25)
        self.assertIn(b"/Count 25", pdf)
        self.assertEqual(pdf.count(b"/Type /Page "), 25)

    def test_fixture_generation_refuses_to_replace_an_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / "existing"
            payload.mkdir()
            (payload / "user-data").write_text("preserve")
            with self.assertRaises(FileExistsError):
                generate_fixtures.create_new_payload_directory(payload)
            self.assertEqual((payload / "user-data").read_text(), "preserve")


if __name__ == "__main__":
    unittest.main()
