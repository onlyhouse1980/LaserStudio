#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMAGE="$ROOT_DIR/Resources/laserstudioicon.jpeg"
TEMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TEMP_DIR/LaserStudio.iconset"
mkdir -p "$ICONSET_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "Missing app icon source image: $SOURCE_IMAGE" >&2
  exit 1
fi

make_icon() {
  local filename="$1"
  local size="$2"
  sips -s format png -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon icon_16x16.png 16
make_icon icon_16x16@2x.png 32
make_icon icon_32x32.png 32
make_icon icon_32x32@2x.png 64
make_icon icon_128x128.png 128
make_icon icon_128x128@2x.png 256
make_icon icon_256x256.png 256
make_icon icon_256x256@2x.png 512
make_icon icon_512x512.png 512
make_icon icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Resources/AppIcon.icns"
