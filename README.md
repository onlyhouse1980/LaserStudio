# LaserStudio

LaserStudio is a macOS design and job sender for Longer Ray5 laser engravers using GRBL over USB.

**A LightBurn alternative for macOS** — a native, free laser engraver software option for Mac users who want to design, position (with camera preview), and send jobs to GRBL laser cutters and engravers. Not affiliated with LightBurn.

Keywords: LightBurn alternative, LightBurn macOS alternative, Mac laser engraver software, GRBL controller for Mac, Longer Ray5 software, laser cutter software macOS.

## Download

Download the latest macOS installer from [GitHub Releases](https://github.com/onlyhouse1980/LaserStudio/releases/latest). The release includes `LaserStudio-macOS.dmg`.

Requires macOS 14 or later. The app is not signed or notarized. If macOS blocks the first launch, Control-click `LaserStudio.app`, choose **Open**, and confirm.

## Build

```sh
./script/build_and_run.sh
```

To create a local installer:

```sh
./script/package_macos.sh
```

Pushing a version tag such as `v1.0.0` starts the GitHub Actions macOS build and publishes the generated DMG as a release download.
