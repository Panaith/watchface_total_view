# project in WatchFace Studio

**Purpose: the original Samsung Watch Face Studio project of Watch Face Total View, kept as the design archive and the source of its screenshots, backgrounds, icons and fonts.**

## Tech Stack

- [Samsung Watch Face Studio](https://developer.samsung.com/watch-face-studio/download.html): the
  project files `src/Watchface Total View 1.wfs` to `5.wfs`, one per design version.
- No code and no build script. The face that is built and installed today is the
  [watchface](../../watchface/documentation/overview.md) app, a hand-written Watch Face Format
  project.

```
project in WatchFace Studio/
├── README.md            # Features and screenshot gallery
├── src/                 # Watch Face Studio project files (.wfs)
├── assets/              # Screenshots and preview images used in the README
├── background_images/   # Background images used in the design
├── fonts/               # Custom fonts: Google - Corinthia (with OFL.txt), WFS - numbers (digit images)
├── icons/               # Icon assets
└── temp.json            # JSON of WFS layer properties (tracked)
```

## Installations

- Watch Face Studio, from the Samsung Developer website (link above).

## How to Develop

1. Launch Watch Face Studio and click **Open Project**.
2. Go to `src/` and open a `.wfs` file: `src/Watchface Total View 5.wfs` is the latest version, 1 to 4 are
   earlier ones.

## How to Debug

Connect a Wear OS watch or emulator and click **Run on Device** in Watch Face Studio.

## How to Build

Watch Face Studio builds the project.

## How to Test and Lint

None beyond running the face on a device from Watch Face Studio.
