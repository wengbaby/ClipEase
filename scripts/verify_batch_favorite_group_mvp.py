#!/usr/bin/env python3
"""Retired by the SQLite-only data baseline.

Favorite state no longer exists in the data model. Keep this shim so older
developer runbooks fail softly instead of asserting removed behavior.
"""

print("SKIP: favorite/group MVP verifier retired; SQLite-only baseline removes favorites")
