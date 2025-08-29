#!/usr/bin/env bash
set -euo pipefail
# Build script to run on macOS. Produces a simulator .app zip artifact for easy copying.
# Usage:
#   ./ios_build_on_mac.sh [project_root] [scheme] [configuration] [target]
# target: simulator (default) or device
# Example:
#   ./ios_build_on_mac.sh /path/to/thermalcamera thermalcamera Debug simulator

PROJECT_DIR="${1:-$(pwd)}"
SCHEME="${2:-thermalcamera}"
CONFIG="${3:-Debug}"
TARGET="${4:-simulator}"
DERIVED_DATA="${PROJECT_DIR}/build"

echo "Building iOS app in $PROJECT_DIR (scheme=$SCHEME, config=$CONFIG, target=$TARGET)"
cd "$PROJECT_DIR"

echo "Installing JS deps..."
npm install

echo "Generating native iOS project (expo prebuild)..."
npx expo prebuild --platform ios

echo "Installing CocoaPods..."
cd ios
pod install --repo-update

cd "$PROJECT_DIR"

if [ "$TARGET" = "simulator" ]; then
	echo "Building simulator (no signing)..."
	xcodebuild -workspace "${SCHEME}.xcworkspace" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphonesimulator -derivedDataPath "$DERIVED_DATA" clean build
	APP_PATH=$(find "$DERIVED_DATA/Build/Products" -path "*$CONFIG-iphonesimulator/*.app" -print -quit || true)
	if [ -z "$APP_PATH" ]; then
		echo "Error: .app not found in derived data" >&2
		exit 2
	fi
	ART_DIR="$PROJECT_DIR/artifacts"
	mkdir -p "$ART_DIR"
	ZIP_PATH="$ART_DIR/${SCHEME}-simulator.zip"
	echo "Packaging $APP_PATH -> $ZIP_PATH"
	rm -f "$ZIP_PATH"
	(cd "$(dirname "$APP_PATH")" && zip -r "$ZIP_PATH" "$(basename "$APP_PATH")")
	echo "Packaged artifact: $ZIP_PATH"
	echo "$ZIP_PATH"
else
	echo "Device/device-archive builds require code signing and are not packaged automatically by this script."
	echo "You can run an archive build manually with xcodebuild archive ..."
fi

echo "iOS build script finished. Derived data: $DERIVED_DATA"
