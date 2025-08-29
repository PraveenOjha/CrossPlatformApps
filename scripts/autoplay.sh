#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage(){
  cat <<USAGE
Usage: $0 [options]

Automates creating a new Expo + TypeScript project and building Android locally.

Options:
  --slug SLUG               Project folder/slug (default: myapp)
  --name NAME               App display name (default: same as slug)
  --android-pkg PKG        Android package name (reverse-DNS)
  --ios-bundle BUNDLE       iOS bundle identifier (reverse-DNS)
  --no-android              Skip Android local build
  --no-ios                  Skip remote iOS build/fetch
  --remote REMOTE           SSH target (e.g. user@mac-host) for iOS build
  --remote-path PATH        Remote project path on mac (required if --remote given)
  --yes                     Non-interactive, accept defaults
  -h, --help                Show this help

Examples:
  $0 --slug myapp --name "My App" --android-pkg com.example.myapp --ios-bundle com.example.myapp --yes
  $0 --slug myapp --remote iMac --remote-path /Users/praveenojha/Desktop/myapp
USAGE
}

SLUG="myapp"
APP_NAME=""
ANDROID_PKG=""
IOS_BUNDLE=""
DO_ANDROID=true
DO_IOS=true
REMOTE=""
REMOTE_PATH=""
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --name) APP_NAME="$2"; shift 2 ;;
    --android-pkg) ANDROID_PKG="$2"; shift 2 ;;
    --ios-bundle) IOS_BUNDLE="$2"; shift 2 ;;
    --no-android) DO_ANDROID=false; shift ;;
    --no-ios) DO_IOS=false; shift ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --remote-path) REMOTE_PATH="$2"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

APP_NAME=${APP_NAME:-$SLUG}

echo "Autoplay: slug=$SLUG name=$APP_NAME android_pkg=$ANDROID_PKG ios_bundle=$IOS_BUNDLE do_android=$DO_ANDROID do_ios=$DO_IOS remote=$REMOTE"

if [ "$ASSUME_YES" != true ]; then
  read -r -p "Proceed with these settings? (y/N): " ok
  if [[ ! "$ok" =~ ^[Yy] ]]; then
    echo "Aborted."; exit 0
  fi
fi

echo "Creating project with npx create-expo-app..."
# create-expo-app does not accept a --name flag reliably; create with slug then update app.json
npx create-expo-app "$SLUG" -t expo-template-blank-typescript

cd "$SLUG"

# update app.json with IDs if provided
if command -v node >/dev/null 2>&1; then
  node -e "const fs=require('fs');const p='app.json';let j=JSON.parse(fs.readFileSync(p));j.expo=j.expo||{};j.expo.name='$APP_NAME';j.expo.slug='$SLUG';j.expo.android=j.expo.android||{};j.expo.ios=j.expo.ios||{}; if('$ANDROID_PKG') j.expo.android.package='$ANDROID_PKG'; if('$IOS_BUNDLE') j.expo.ios.bundleIdentifier='$IOS_BUNDLE'; fs.writeFileSync(p,JSON.stringify(j,null,2)); console.log('Updated app.json');"
else
  echo "Please edit app.json to set android package / ios bundle id (node not available)."
fi

echo "Installing JS dependencies..."
npm install

echo "Generating native projects (expo prebuild)..."
npx expo prebuild --platform all

# Build Android local if requested
if [ "$DO_ANDROID" = true ]; then
  if [ -d android ]; then
    echo "Building Android debug APK..."
    pushd android >/dev/null
    # Create local.properties if Android SDK env var is present
    if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ ! -f local.properties ]; then
      echo "sdk.dir=${ANDROID_SDK_ROOT}" > local.properties
      echo "Wrote local.properties with ANDROID_SDK_ROOT"
    fi
    ./gradlew assembleDebug -x lint
    popd >/dev/null
    mkdir -p ../artifacts/$SLUG
    cp android/app/build/outputs/apk/debug/app-debug.apk ../artifacts/$SLUG/ || true
    echo "Android APK copied to artifacts/$SLUG/ (if build succeeded)"
  else
    echo "No android/ directory found, skipping Android build"
  fi
fi

# Remote iOS build and fetch (automatically, without extra prompts)
if [ "$DO_IOS" = true ]; then
  # Default to SSH alias 'iMac' and Desktop path if not provided
  if [ -z "${REMOTE:-}" ]; then
    REMOTE="iMac"
  fi
  if [ -z "${REMOTE_PATH:-}" ]; then
    REMOTE_PATH="/Users/praveenojha/Desktop/$SLUG"
  fi

  echo "Triggering remote iOS build on $REMOTE for project at $REMOTE_PATH (non-interactive)"
  # call the SSH wrapper which runs the mac build script and rsyncs the artifact back
  if ./scripts/build_ios_via_ssh.sh "$REMOTE" "$REMOTE_PATH"; then
    echo "Remote build+fetch completed; check artifacts/ios for zip"
  else
    echo "Remote build failed or fetch failed. Check remote logs or confirm SSH access and paths." >&2
  fi
fi

echo "Autoplay finished. Artifacts (if any) are under artifacts/"
