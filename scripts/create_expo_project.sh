#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "Create new Expo + TypeScript project helper"

read -r -p "Target folder name / slug (e.g. myapp): " SLUG
if [ -z "$SLUG" ]; then
  echo "Slug cannot be empty." >&2
  exit 1
fi

read -r -p "Display name (App name shown on device) [${SLUG}]: " APP_NAME
APP_NAME=${APP_NAME:-$SLUG}

read -r -p "Android package (reverse-DNS, e.g. com.example.myapp): " ANDROID_PKG
read -r -p "iOS bundle id (reverse-DNS, e.g. com.example.myapp): " IOS_BUNDLE

read -r -p "Template (default: expo-template-blank-typescript): " TEMPLATE
TEMPLATE=${TEMPLATE:-expo-template-blank-typescript}

read -r -p "Run npm install after create? (Y/n): " INSTALL_ANS
INSTALL_ANS=${INSTALL_ANS:-Y}

read -r -p "Run 'npx expo prebuild --platform all' after create? (Y/n): " PREBUILD_ANS
PREBUILD_ANS=${PREBUILD_ANS:-Y}

echo
echo "Summary"
echo "  Folder/slug: $SLUG"
echo "  App name:   $APP_NAME"
echo "  Android pkg: $ANDROID_PKG"
echo "  iOS bundle:  $IOS_BUNDLE"
echo "  Template:    $TEMPLATE"
echo
read -r -p "Proceed and create project? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
  echo "Aborted by user."
  exit 0
fi

echo "Creating project '$SLUG'..."
npx create-expo-app "$SLUG" -t "$TEMPLATE" --name "$APP_NAME"

cd "$SLUG"

# Update app.json with provided IDs using node if available
if command -v node >/dev/null 2>&1; then
  node - <<NODE
const fs=require('fs');
const p='app.json';
const raw=fs.readFileSync(p,'utf8');
const j=JSON.parse(raw);
j.expo = j.expo || {};
j.expo.name = process.env.EXPO_APP_NAME || '$APP_NAME';
j.expo.slug = process.env.EXPO_SLUG || '$SLUG';
j.expo.android = j.expo.android || {};
j.expo.ios = j.expo.ios || {};
if ('$ANDROID_PKG' && '$ANDROID_PKG' !== '') j.expo.android.package = '$ANDROID_PKG';
if ('$IOS_BUNDLE' && '$IOS_BUNDLE' !== '') j.expo.ios.bundleIdentifier = '$IOS_BUNDLE';
fs.writeFileSync(p, JSON.stringify(j,null,2));
console.log('Updated',p);
NODE
else
  echo "Warning: node not found. Please edit app.json manually to set bundle/package ids."
fi

if [[ "$INSTALL_ANS" =~ ^[Yy] ]]; then
  echo "Installing dependencies (may take a few minutes)..."
  npm install
fi

if [[ "$PREBUILD_ANS" =~ ^[Yy] ]]; then
  echo "Running expo prebuild --platform all"
  npx expo prebuild --platform all
fi

# Save a prompt file describing this project for future automation
mkdir -p ../tools/create_expo/projects || true
cat > ../tools/create_expo/projects/${SLUG}.prompt.json <<JSON
{
  "slug": "$SLUG",
  "name": "$APP_NAME",
  "android_package": "$ANDROID_PKG",
  "ios_bundle": "$IOS_BUNDLE",
  "template": "$TEMPLATE",
  "created_at": "$(date --iso-8601=seconds)"
}
JSON

echo "Created prompt record at ../tools/create_expo/projects/${SLUG}.prompt.json"
echo "Project '$SLUG' ready. See README.md in tools/create_expo for next steps."
