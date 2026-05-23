# ClipEase

ClipEase is a lightweight macOS menu bar clipboard history app.

It keeps recent clipboard content close at hand, supports quick search and paste,
and stays out of the way while you work.

## Features

- Menu bar app with a compact history window
- Clipboard history for text, images, links, colors, rich text, and files
- Search, filter, favorite, group, preview, edit, and delete entries
- Quick paste with double click, Return, and keyboard shortcuts
- Pause recording and ignore selected apps
- Local storage, export, import, and backup utilities

## Requirements

- macOS 13.0 or later
- Swift 6.1 or later for source builds

## Build

Build the Swift package:

```bash
swift build -c release --product ClipEase
```

Build a macOS app bundle:

```bash
scripts/build-app.sh --bump none
```

Build and launch the app:

```bash
scripts/build-app.sh --bump none --run
```

The app bundle is written to `.build/ClipEase.app`.

## Repository Structure

```text
.
├── Package.swift
├── README.md
├── Resources/
│   ├── ClipEase.icns
│   ├── Info.plist
│   └── Sounds/
├── Sources/
│   └── ClipEase/
├── docs/
│   └── README.md
└── scripts/
    ├── build-app.sh
    └── bump_version.py
```

## Documentation

See [docs/README.md](docs/README.md) for a brief description of the public
repository layout.

## License

No license has been published for this repository yet.
