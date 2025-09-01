#!/usr/bin/env bash
set -euo pipefail

# Canonical per-app remote iOS build helper template.
# This file is copied into the generated app folder (apps/<slug>/remote_ios_build.sh)
# so edits here persist and are propagated when creating new apps.

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo "Remote iOS build helper template loaded for $PROJECT_NAME"
# CLI: support --no-pod/--skip-pod, and remote orchestration flags.
SKIP_POD=false
REMOTE_HOST=""
REMOTE_PATH=""
REMOTE_HELPER=false
FETCH_ARTIFACTS=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pod|--skip-pod)
      SKIP_POD=true; shift ;;
    --remote-host)
      REMOTE_HOST="$2"; shift 2 ;;
    --remote-path)
      REMOTE_PATH="$2"; shift 2 ;;
    --remote-helper)
      # Indicates the script is running on the remote mac and should only perform the build steps
      REMOTE_HELPER=true; shift ;;
    --no-fetch-artifacts)
      FETCH_ARTIFACTS=false; shift ;;
    *)
      echo "Warning: unknown arg $1"; shift ;;
  esac
done

# Ensure Homebrew/bin and UTF-8 locale are available for non-interactive shells
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Defaults: use the standard SSH target and a Desktop path if none provided
if [ -z "$REMOTE_HOST" ]; then
  REMOTE_HOST="praveenojha@192.168.2.18"
fi
if [ -z "$REMOTE_PATH" ]; then
  REMOTE_PATH="/Volumes/data/work/$PROJECT_NAME"
fi

# If a remote host was provided and we're NOT running in remote-helper mode,
# act as the client: rsync project to remote and invoke the helper there.
if [ -n "$REMOTE_HOST" ] && [ "$REMOTE_HELPER" = false ]; then
  # Default remote path if not provided
  if [ -z "$REMOTE_PATH" ]; then
    REMOTE_PATH="/Users/praveenojha/Desktop/$PROJECT_NAME"
  fi

  echo "Orchestrating remote build: syncing to $REMOTE_HOST:$REMOTE_PATH"
  # Ensure remote path exists
  ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_PATH'"

  # Rsync project to remote (exclude build artifacts)
  rsync -avz --delete \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude 'android/.gradle' \
    --exclude 'android/app/build' \
    --exclude 'ios/Pods' \
    --exclude 'artifacts' \
    ./ "$REMOTE_HOST:$REMOTE_PATH/"

  # Forward skip-pod flag if set
  REMOTE_POD_FLAG=""
  if [ "$SKIP_POD" = true ]; then
    REMOTE_POD_FLAG="--skip-pod"
  fi

  echo "Invoking remote helper on $REMOTE_HOST (cd $REMOTE_PATH && ./remote_ios_build.sh --remote-helper $REMOTE_POD_FLAG)"
  if ssh "$REMOTE_HOST" "bash -lc 'cd \"$REMOTE_PATH\" && ./remote_ios_build.sh --remote-helper $REMOTE_POD_FLAG'"; then
    echo "Remote build completed."
    # Fetch artifacts back if requested
    if [ "$FETCH_ARTIFACTS" = true ]; then
      mkdir -p "$PROJECT_DIR/artifacts/ios"
      rsync -avz "$REMOTE_HOST:$REMOTE_PATH/artifacts/ios/" "$PROJECT_DIR/artifacts/ios/" || true
      echo "Artifacts fetched to $PROJECT_DIR/artifacts/ios"
    fi
    exit 0
  else
    echo "Remote helper failed on $REMOTE_HOST" >&2
    exit 5
  fi
fi

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
