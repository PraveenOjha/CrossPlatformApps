#!/usr/bin/env bash
set -euo pipefail

# Canonical per-app remote iOS build helper template.
# This file is copied into the generated app folder (apps/<slug>/remote_ios_build.sh)
# so edits here persist and are propagated when creating new apps.

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo "Remote iOS build helper template loaded for $PROJECT_NAME"

# Simple CLI: support --no-pod or --skip-pod to speed iterative builds
SKIP_POD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pod|--skip-pod)
      SKIP_POD=true; shift ;;
    *)
      echo "Warning: unknown arg $1"; shift ;;
  esac
done

# Ensure Homebrew/bin and UTF-8 locale are available for non-interactive shells
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Install JS deps
if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi

# Ensure native projects are generated
npx expo prebuild --platform ios || true

# Enter ios folder and install pods if needed
if [ -d ios ]; then
  cd ios
  if [ -f Podfile ]; then
    if [ "$SKIP_POD" = true ]; then
      echo "Skipping 'pod install' due to --skip-pod/--no-pod flag"
    else
      echo "Running pod install --repo-update (with UTF-8 locale)"
      LANG="${LANG}" LC_ALL="${LC_ALL}" pod install --repo-update || true
    fi
  fi
  cd ..
else
  echo "No ios/ directory found after prebuild; aborting" >&2
  exit 2
fi

# Detect workspace/project and build simulator using the actual file paths
WORKSPACE_PATH=""
PROJECT_PATH=""
# Prefer directory entries to avoid picking up inner files like contents.xcworkspacedata
WORKSPACE_PATH=$(find ios -maxdepth 1 -type d -name "*.xcworkspace" -print | head -n1 || true)
PROJECT_PATH=$(find ios -maxdepth 1 -type d -name "*.xcodeproj" -print | head -n1 || true)

if [ -n "$WORKSPACE_PATH" ]; then
  SCHEME_NAME="$(basename "$WORKSPACE_PATH" .xcworkspace)"
  echo "Building workspace: $WORKSPACE_PATH scheme: $SCHEME_NAME"
  xcodebuild -workspace "$WORKSPACE_PATH" -scheme "$SCHEME_NAME" -configuration Release -sdk iphonesimulator -derivedDataPath ios-build || true
elif [ -n "$PROJECT_PATH" ]; then
  SCHEME_NAME="$(basename "$PROJECT_PATH" .xcodeproj)"
  echo "Building project: $PROJECT_PATH scheme: $SCHEME_NAME"
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -configuration Release -sdk iphonesimulator -derivedDataPath ios-build || true
else
  echo "No .xcworkspace or .xcodeproj found under ios/. Cannot run xcodebuild." >&2
  exit 4
fi

# Find built .app and zip it
APP_PATH=$(find ios-build -type d -name "*.app" | head -n1 || true)
if [ -n "$APP_PATH" ]; then
  mkdir -p artifacts/ios
  ZIPNAME="${PROJECT_NAME}-simulator.zip"
  rm -f "artifacts/ios/$ZIPNAME"
  pushd "$(dirname "$APP_PATH")" >/dev/null
  zip -r "$PROJECT_DIR/artifacts/ios/$ZIPNAME" "$(basename "$APP_PATH")"
  popd >/dev/null
  echo "Packaged simulator app: $PROJECT_DIR/artifacts/ios/$ZIPNAME"
  exit 0
else
  echo "xcodebuild did not produce a .app. See xcodebuild output above." >&2
  exit 3
fi
