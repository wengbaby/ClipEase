# Documentation

This directory contains public, non-sensitive repository notes for ClipEase.

## Repository Layout

```text
.
├── Package.swift
├── README.md
├── Resources/
├── Sources/
├── docs/
└── scripts/
```

## Directory Notes

| Path | Description |
| --- | --- |
| `Package.swift` | Swift package definition for the ClipEase executable target. |
| `Resources/` | App bundle resources, including `Info.plist`, icon assets, and sounds. |
| `Sources/ClipEase/` | Swift source code for the macOS app. |
| `Sources/ClipEase/App/` | App lifecycle, menu bar, and status item code. |
| `Sources/ClipEase/Core/` | Models, storage, settings, services, and shared utilities. |
| `Sources/ClipEase/Features/` | User-facing app features such as history, settings, paste execution, and help. |
| `scripts/build-app.sh` | Helper script for building `.build/ClipEase.app`. |
| `scripts/bump_version.py` | Version helper used by `scripts/build-app.sh`. |

## Build Output

Generated files are not part of the public source tree:

- `.build/`
- `dist/`
- local Xcode and SwiftPM user state
