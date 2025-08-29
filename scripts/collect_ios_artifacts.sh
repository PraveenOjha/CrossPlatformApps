#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <user@mac-host> <remote-build-dir> [remote-artifact-path]"
  echo "Example: $0 iMac /Users/praveenojha/Desktop/thermalcamera ~/Desktop/thermalcamera/build/Build/Products/Debug-iphonesimulator/thermalcamera.app"
  exit 1
fi

REMOTE="$1"
REMOTE_DIR="$2"
REMOTE_ARTIFACT="${3:-$REMOTE_DIR/ios/build/Build/Products/Debug-iphonesimulator/thermalcamera.app}"

DEST="artifacts/ios"
mkdir -p "$DEST"

echo "Copying $REMOTE:$REMOTE_ARTIFACT to $DEST"
rsync -avz --delete "$REMOTE:$REMOTE_ARTIFACT" "$DEST/" || scp -r "$REMOTE:$REMOTE_ARTIFACT" "$DEST/"
echo "Done. Files in $DEST:"
ls -la "$DEST"
