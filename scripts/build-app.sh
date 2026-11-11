#!/usr/bin/env bash
# Baut "Paper Renamer.app" (und optional ein DMG) aus den Swift-Quellen.
#
#   ./scripts/build-app.sh             # baut build/Paper Renamer.app für diesen Mac
#   ./scripts/build-app.sh --install   # ... und kopiert die App nach /Applications
#   ./scripts/build-app.sh --universal # Apple Silicon + Intel in einer App
#   ./scripts/build-app.sh --dmg       # erzeugt zusätzlich build/PaperRenamer.dmg
#
# Voraussetzung: Xcode oder die Command Line Tools (xcode-select --install).
set -euo pipefail

APP_NAME="Paper Renamer"
EXECUTABLE="PaperRenamer"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

INSTALL=0
UNIVERSAL=0
DMG=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --dmg) DMG=1 ;;
    *) echo "Unbekannte Option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Dieses Skript muss auf einem Mac ausgeführt werden." >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Swift wurde nicht gefunden. Bitte zuerst ausführen: xcode-select --install" >&2
  exit 1
fi

cd "$ROOT"

if [[ $UNIVERSAL -eq 1 ]]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi

BINARIES=()
for arch in "${ARCHS[@]}"; do
  echo "==> Kompiliere für $arch …"
  swift build -c release --arch "$arch" --product "$EXECUTABLE"
  BIN_DIR="$(swift build -c release --arch "$arch" --show-bin-path)"
  BINARIES+=("$BIN_DIR/$EXECUTABLE")
done

echo "==> Erstelle $APP_NAME.app …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$EXECUTABLE"
else
  cp "${BINARIES[0]}" "$APP/Contents/MacOS/$EXECUTABLE"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Erweiterte Attribute (z. B. Quarantäne aus einem ZIP-Download) entfernen, sonst scheitert codesign.
xattr -cr "$APP"
# Ad-hoc-Signatur (nötig auf Apple Silicon; keine Apple-Developer-ID erforderlich).
codesign --force --sign - --timestamp=none "$APP"
echo "==> Fertig: $APP"

if [[ $DMG -eq 1 ]]; then
  echo "==> Erstelle DMG …"
  STAGING="$BUILD_DIR/dmg"
  rm -rf "$STAGING" "$BUILD_DIR/PaperRenamer.dmg"
  mkdir -p "$STAGING"
  ditto "$APP" "$STAGING/$APP_NAME.app"
  ln -s /Applications "$STAGING/Programme"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/PaperRenamer.dmg" >/dev/null
  rm -rf "$STAGING"
  echo "==> Fertig: $BUILD_DIR/PaperRenamer.dmg"
fi

if [[ $INSTALL -eq 1 ]]; then
  TARGET="/Applications/$APP_NAME.app"
  echo "==> Installiere nach $TARGET …"
  osascript -e "if application \"$APP_NAME\" is running then tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  echo "==> Installiert. Starte die App …"
  open "$TARGET"
fi
