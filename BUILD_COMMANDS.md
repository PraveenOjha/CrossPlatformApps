iOS (remote mac)
## Build commands and helper scripts

This file summarizes the commands and scripts used to build Android locally and iOS on a remote mac.

Android (local machine)

- Install dependencies:
  npm install
- Generate native projects (only required once or when native config changes):
  npx expo prebuild --platform android
- Build debug APK (from android/):
  cd apps/<your-app>/android && ./gradlew assembleDebug -x lint
- Local artifact path:
  apps/<your-app>/android/app/build/outputs/apk/debug/app-debug.apk

iOS (remote mac)

On the mac ensure:
- Xcode + xcode-select command line tools
- CocoaPods, Node.js/npm
- LANG set to UTF-8 in the shell: export LANG=en_US.UTF-8

Typical mac-side sequence (run on the mac inside project root):

- npm install
- npx expo prebuild --platform ios
- cd ios && pod install --repo-update
- xcodebuild -workspace <workspace>.xcworkspace -scheme <scheme> -configuration Debug -sdk iphonesimulator -derivedDataPath build clean build

Remote helpers (from Linux host)

- Copy project to mac (rsync):
  rsync -av --exclude node_modules --exclude ios/Pods ./ user@mac-host:/path/to/project
- Trigger mac-side build via SSH (wrapper):
  ./scripts/build_ios_via_ssh.sh user@mac-host /path/on/mac/to/project

Collect artifacts
- Use `scripts/collect_ios_artifacts.sh` to fetch simulator .app or signed .ipa from the mac to this repo's `artifacts/` directory.

Notes

- If SSH drops during long builds, use `screen`/`tmux` on the mac or run mac-side build in background and tail build logs.
- Device/archive builds require code signing and additional manual steps on the mac; the scripts focus on simulator and debug flows.
