#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Canonical per-app Android build helper.
# This file is copied into apps/<slug>/android_build.sh by autoplay.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo "Android build helper running in $PROJECT_DIR"

# flags
SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build|--skip-build) SKIP_BUILD=true; shift ;;
    *) echo "Warning: unknown arg $1"; shift ;;
  esac
done

# If no android/ directory, nothing to do
if [ ! -d "$PROJECT_DIR/android" ]; then
  echo "No android/ directory found. Run 'npx expo prebuild --platform android' first or ensure native project exists."
  exit 0
fi

# Ensure local.properties contains SDK path (detect common locations)
if [ ! -f "$PROJECT_DIR/android/local.properties" ]; then
  SDK_PATH=""
  if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    SDK_PATH="${ANDROID_SDK_ROOT}"
  fi
  if [ -z "$SDK_PATH" ] && [ -n "${ANDROID_HOME:-}" ]; then
    SDK_PATH="${ANDROID_HOME}"
  fi
  if [ -z "$SDK_PATH" ] && [ -d "$HOME/Android/Sdk" ]; then
    SDK_PATH="$HOME/Android/Sdk"
  fi
  if [ -z "$SDK_PATH" ] && [ -d "/home/praveen/Work/Android/sdk" ]; then
    SDK_PATH="/home/praveen/Work/Android/sdk"
  fi
  if [ -z "$SDK_PATH" ] && [ -d "/opt/android-sdk" ]; then
    SDK_PATH="/opt/android-sdk"
  fi
  if [ -z "$SDK_PATH" ] && [ -d "/usr/lib/android-sdk" ]; then
    SDK_PATH="/usr/lib/android-sdk"
  fi

  if [ -n "$SDK_PATH" ]; then
    echo "sdk.dir=${SDK_PATH}" > "$PROJECT_DIR/android/local.properties"
    export ANDROID_SDK_ROOT="$SDK_PATH"
    echo "Wrote android/local.properties with SDK_PATH=${SDK_PATH}"
  else
    echo "Warning: Android SDK location not found. Please set ANDROID_SDK_ROOT or ANDROID_HOME, or create android/local.properties manually." >&2
  fi
else
  echo "Found existing android/local.properties"
fi

# Install JS deps if necessary
if [ -f "$PROJECT_DIR/package-lock.json" ]; then
  (cd "$PROJECT_DIR" && npm ci)
else
  (cd "$PROJECT_DIR" && npm install)
fi

# Prebuild if android native project not present (safe no-op if already present)
(cd "$PROJECT_DIR" && npx expo prebuild --platform android) || true

if [ "$SKIP_BUILD" = true ]; then
  echo "--skip-build specified; skipping Gradle build."
else
  echo "Running Gradle assembleDebug..."
  pushd "$PROJECT_DIR/android" >/dev/null
  ./gradlew assembleDebug -x lint
  popd >/dev/null
fi

# Copy APK into per-app artifacts folder
mkdir -p "$PROJECT_DIR/artifacts"
APK_PATH="$PROJECT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK_PATH" ]; then
  cp -f "$APK_PATH" "$PROJECT_DIR/artifacts/" || true
  echo "APK copied to $PROJECT_DIR/artifacts/"
else
  echo "APK not found at expected path: $APK_PATH" >&2
fi

echo "Android build helper finished."
