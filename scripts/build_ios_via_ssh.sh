#!/usr/bin/env bash
set -euo pipefail
# Usage:
# ./build_ios_via_ssh.sh user@mac-host /path/to/project [branch-or-commit]

REMOTE="$1"
PROJECT_PATH="$2"
REF="${3:-HEAD}"

LOCAL_DEST="artifacts/ios"
mkdir -p "$LOCAL_DEST"

echo "Running remote iOS build on $REMOTE for $PROJECT_PATH (ref=$REF)"
# If remote path doesn't exist, try to rsync a local folder with the same basename
echo "Checking remote path exists..."
if ! ssh "$REMOTE" test -d "$PROJECT_PATH" 2>/dev/null; then
	BASENAME=$(basename "$PROJECT_PATH")
	LOCAL_DIR="$(pwd)/${BASENAME}"
	if [ -d "$LOCAL_DIR" ]; then
		REMOTE_PARENT=$(dirname "$PROJECT_PATH")
		echo "Remote path not found. Rsyncing local $LOCAL_DIR to $REMOTE:$REMOTE_PARENT/"
		rsync -av --exclude node_modules --exclude ios/Pods "$LOCAL_DIR" "$REMOTE:$REMOTE_PARENT/"
	# Also rsync our repo-level scripts into the remote project so helper scripts are available
	echo "Rsyncing helper scripts to remote project..."
	rsync -av --delete scripts/ "$REMOTE:$REMOTE_PARENT/$(basename "$LOCAL_DIR")/scripts/" || true
	else
		echo "Remote path $PROJECT_PATH does not exist and local folder $LOCAL_DIR not found. Aborting." >&2
		exit 2
	fi
else
	echo "Remote path exists. Proceeding to build."
	# Ensure helper scripts are present/updated on remote project
	REMOTE_PROJ="$PROJECT_PATH"
	echo "Syncing local helper scripts to remote project path $REMOTE_PROJ/scripts/"
	rsync -av --delete scripts/ "$REMOTE:$REMOTE_PROJ/scripts/" || true
fi

ssh "$REMOTE" bash -s -- "$PROJECT_PATH" "$REF" <<'SSH'
set -euo pipefail
PROJECT_PATH="$1"
REF="${2:-HEAD}"
echo "Changing to project path: $PROJECT_PATH"
cd "$PROJECT_PATH" || { echo "Remote project path $PROJECT_PATH not found" >&2; exit 1; }

echo "Remote: ensuring git operations only if repo exists"
if [ -d .git ]; then
	echo "Git repo detected on remote; fetching updates..."
	git fetch --all || true
	git checkout "$REF" || true
	git pull || true
else
	echo "No .git on remote; skipping git operations."
fi

export LANG=en_US.UTF-8

if ! command -v npm >/dev/null 2>&1; then
	echo "npm not found on remote. Attempting to install Node/npm and CocoaPods..."
	if command -v brew >/dev/null 2>&1; then
		echo "Homebrew detected on remote. Installing node and cocoapods via brew..."
		brew update || true
		brew install node || true
		brew install cocoapods || true
	else
		echo "Homebrew not found on remote. Attempting non-interactive Homebrew install..."
		# Try non-interactive Homebrew install (may still require user interaction on some systems)
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
		# Try to load brew into environment for both common locations
		if [ -f /opt/homebrew/bin/brew ]; then
			eval "$(/opt/homebrew/bin/brew shellenv)" || true
		elif [ -f /usr/local/bin/brew ]; then
			eval "$(/usr/local/bin/brew shellenv)" || true
		fi
		if command -v brew >/dev/null 2>&1; then
			echo "Homebrew installed. Installing node and cocoapods via brew..."
			brew update || true
			brew install node || true
			brew install cocoapods || true
		else
			echo "Homebrew install failed or not available. Trying gem install for cocoapods and pkg for node as fallback..."
			sudo gem install cocoapods || true
			# Try to download and run Node installer pkg for mac (arch-specific)
			ARCH=$(uname -m)
			if [ "$ARCH" = "arm64" ]; then
				NODE_PKG_NAME=$(curl -sL https://nodejs.org/dist/latest/ | grep -oE 'node-v[0-9]+\.[0-9]+\.[0-9]+-darwin-arm64.pkg' | head -n1)
			else
				NODE_PKG_NAME=$(curl -sL https://nodejs.org/dist/latest/ | grep -oE 'node-v[0-9]+\.[0-9]+\.[0-9]+-darwin-x64.pkg' | head -n1)
			fi
			if [ -n "$NODE_PKG_NAME" ]; then
				NODE_PKG_URL="https://nodejs.org/dist/latest/$NODE_PKG_NAME"
				echo "Downloading Node pkg: $NODE_PKG_URL"
				curl -LO "$NODE_PKG_URL" || true
				echo "Attempting to run installer (may require sudo password)..."
				sudo installer -pkg "$NODE_PKG_NAME" -target / || true
			else
				echo "Could not find Node pkg to download. Please install Node/npm on the mac manually." >&2
			fi
		fi
	fi
fi

if ! command -v npm >/dev/null 2>&1; then
	echo "npm still not available on remote after attempted installs. Aborting remote build." >&2
	exit 3
fi

echo "Running npm install and prebuild on remote..."
npm install
npx expo prebuild --platform ios

cd ios || exit 1
pod install --repo-update || true
cd ..

echo "Detecting Xcode workspace/scheme on remote..."
SCHEME=""
if [ -d ios ]; then
	# prefer workspace
	if ls ios/*.xcworkspace >/dev/null 2>&1; then
		WS=$(ls ios/*.xcworkspace | head -n1)
		SCHEME=$(basename "$WS" .xcworkspace)
	elif ls ios/*.xcodeproj >/dev/null 2>&1; then
		P=$(ls ios/*.xcodeproj | head -n1)
		SCHEME=$(basename "$P" .xcodeproj)
	fi
fi
if [ -z "$SCHEME" ]; then
	# fallback: use basename of project path with camel case
	BASENAME=$(basename "$PROJECT_PATH")
	SCHEME="$(echo "$BASENAME" | awk 'BEGIN{FS="-";OFS=""}{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2) }}1')"
fi
echo "Using scheme: $SCHEME"

echo "Invoking mac-side iOS build script..."
./scripts/ios_build_on_mac.sh "$PROJECT_PATH" "$SCHEME" Debug simulator 2>&1 | tee build.log
echo "BUILD_ZIP=${PROJECT_PATH}/artifacts/${SCHEME}-simulator.zip"
SSH

echo "Fetching artifact from remote..."
rsync -avz --progress "$REMOTE:${PROJECT_PATH}/artifacts/thermalcamera-simulator.zip" "$LOCAL_DEST/" || scp "$REMOTE:${PROJECT_PATH}/artifacts/thermalcamera-simulator.zip" "$LOCAL_DEST/"
echo "Fetched artifact to $LOCAL_DEST"
