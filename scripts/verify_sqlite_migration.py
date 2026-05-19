#!/usr/bin/env python3
"""Compatibility wrapper for the retired SQLite migration verifier."""

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


if __name__ == "__main__":
    print("NOTE: SQLite migration verification retired; running SQLite-only baseline verifier.")
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts/verify_sqlite_only_baseline.py")],
        cwd=ROOT,
    )
    sys.exit(result.returncode)
