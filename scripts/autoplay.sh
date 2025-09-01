#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Directory of this script (absolute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  $0 --slug myapp --remote iMac --remote-path /Volumes/data/work/myapp
USAGE
}

SLUG="myapp"
APP_NAME=""
ANDROID_PKG=""
IOS_BUNDLE=""
DO_ANDROID=true
DO_IOS=true
REMOTE="praveenojha@192.168.2.18"
REMOTE_PATH=""
ASSUME_YES=false
CLEANUP=false
SKIP_POD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --name) APP_NAME="$2"; shift 2 ;;
    --android-pkg) ANDROID_PKG="$2"; shift 2 ;;
    --ios-bundle) IOS_BUNDLE="$2"; shift 2 ;;
    --no-android) DO_ANDROID=false; shift ;;
    --no-ios) DO_IOS=false; shift ;;
    --no-pod|--skip-pod) SKIP_POD=true; shift ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --remote-path) REMOTE_PATH="$2"; shift 2 ;;
  --cleanup) CLEANUP=true; shift ;;
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

if [ "$CLEANUP" = true ]; then
  if [ "$ASSUME_YES" != true ]; then
    read -r -p "Confirm cleanup of local build caches for project '$SLUG'? This will remove ios-build, ios/Pods, android build dirs under apps/$SLUG (y/N): " okc
    if [[ ! "$okc" =~ ^[Yy] ]]; then
      echo "Cleanup aborted by user."; exit 0
    fi
  fi
  echo "Running local cleanup for apps/$SLUG..."
  rm -rf "apps/$SLUG/ios-build" "apps/$SLUG/ios/build" "apps/$SLUG/ios/Pods" "apps/$SLUG/android/.gradle" "apps/$SLUG/android/app/build" || true
  echo "Local cleanup complete."

  if [ -n "${REMOTE:-}" ] && [ -n "${REMOTE_PATH:-}" ]; then
    if [ "$ASSUME_YES" != true ]; then
      read -r -p "Also remove build caches on remote $REMOTE at $REMOTE_PATH? (y/N): " okr
      if [[ ! "$okr" =~ ^[Yy] ]]; then
        echo "Remote cleanup skipped.";
      else
        echo "Removing remote build caches..."
        ssh "$REMOTE" "rm -rf '$REMOTE_PATH/ios-build' '$REMOTE_PATH/ios/Pods' '$REMOTE_PATH/ios/build' '$REMOTE_PATH/android/.gradle' '$REMOTE_PATH/android/app/build' '$REMOTE_PATH/artifacts' || true"
        echo "Remote cleanup complete."
      fi
    else
      echo "Removing remote build caches on $REMOTE (non-interactive)..."
      ssh "$REMOTE" "rm -rf '$REMOTE_PATH/ios-build' '$REMOTE_PATH/ios/Pods' '$REMOTE_PATH/ios/build' '$REMOTE_PATH/android/.gradle' '$REMOTE_PATH/android/app/build' '$REMOTE_PATH/artifacts' || true"
      echo "Remote cleanup complete."
    fi
  fi

  echo "Cleanup finished."; exit 0
fi

APP_DIR="apps/$SLUG"
if [ -d "$APP_DIR" ]; then
  echo "Project directory $APP_DIR already exists — using existing project and proceeding to build."
else
  echo "Creating project under apps/ with npx create-expo-app..."
  # create-expo-app does not accept a --name flag reliably; create under apps/ then update app.json
  npx create-expo-app "$APP_DIR" -t expo-template-blank-typescript
fi

# Change into the app directory (existing or newly created)
cd "$APP_DIR"

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

# Create per-app remote iOS build helper so autoplay always produces it at create time
if [ -f "$SCRIPT_DIR/remote_ios_build.sh" ]; then
  # If a canonical template exists under scripts/, copy it into the app so it persists per-app
  if [ ! -f remote_ios_build.sh ]; then
    cp "$SCRIPT_DIR/remote_ios_build.sh" ./remote_ios_build.sh || true
    chmod +x remote_ios_build.sh || true
    echo "Copied canonical per-app remote build helper into: $(pwd)/remote_ios_build.sh"
  fi
else
  echo "Warning: canonical scripts/remote_ios_build.sh not found; no per-app helper created"
fi

# Copy canonical android build helper into app so per-app builds are possible
if [ -f "$SCRIPT_DIR/android_build.sh" ]; then
  if [ ! -f android_build.sh ]; then
    cp "$SCRIPT_DIR/android_build.sh" ./android_build.sh || true
    chmod +x android_build.sh || true
    echo "Copied canonical per-app Android build helper into: $(pwd)/android_build.sh"
  fi
else
  echo "Warning: canonical scripts/android_build.sh not found; no per-app android helper created"
fi

# Build Android local if requested
if [ "$DO_ANDROID" = true ]; then
  if [ -d android ]; then
    echo "Building Android debug APK..."
    pushd android >/dev/null
    # Create local.properties by detecting Android SDK in common locations if not already present
    if [ ! -f local.properties ]; then
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
      # user-provided SDK location (fallback)
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
        # export for this script run so gradle can find tools if it runs in this session
        export ANDROID_SDK_ROOT="$SDK_PATH"
        echo "sdk.dir=${SDK_PATH}" > local.properties
        echo "Wrote local.properties with SDK_PATH=${SDK_PATH} and exported ANDROID_SDK_ROOT"
      else
        echo "Warning: Android SDK location not found. Please set ANDROID_SDK_ROOT or ANDROID_HOME, or create android/local.properties manually." >&2
      fi
    fi
    ./gradlew assembleDebug -x lint
    popd >/dev/null
  # Place Android APK into the per-app artifacts folder so both platforms' artifacts live together
  mkdir -p ./artifacts
  cp android/app/build/outputs/apk/debug/app-debug.apk ./artifacts/ || true
  echo "Android APK copied to $(pwd)/artifacts/ (if build succeeded)"
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

  # Delegate SSH/rsync orchestration to per-app remote_ios_build.sh by invoking it locally
  # The per-app script will rsync and invoke the helper on the remote host when given --remote-host/--remote-path.
  REMOTE_ARGS="--remote-host \"$REMOTE\" --remote-path \"$REMOTE_PATH\""
  if [ "$SKIP_POD" = true ]; then
    REMOTE_ARGS="$REMOTE_ARGS --skip-pod"
  fi

  # Call the per-app helper (it will handle rsync->ssh->build->fetch)
  if ./remote_ios_build.sh $REMOTE_ARGS; then
    echo "Remote build orchestration completed; artifacts (if any) are under artifacts/$SLUG/ios"
  else
    echo "Remote orchestration failed. Check logs and remote machine access." >&2
  fi
fi

echo "Autoplay finished. Artifacts (if any) are under artifacts/"
