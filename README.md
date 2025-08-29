
Checklist
- Create an Expo app scaffold (TypeScript)
- Generate native projects and convert Android to Kotlin and iOS to Swift
- Build & verify Android locally with Android Studio
- Build & verify iOS remotely over SSH (Xcode machine)

Quick plan
1) Create the Expo TypeScript app
2) Run `expo prebuild` to generate `android/` and `ios/`
3) Convert Android `MainActivity` to Kotlin and enable Kotlin in Gradle
4) Add a Swift file to the Xcode project to enable Swift bridging
5) Build and verify: use Android Studio / Gradle locally; use `xcodebuild` remotely via SSH for iOS

What I scaffolded here
- `package.json`, `app.json`, `tsconfig.json`
- `src/App.tsx` minimal TypeScript app
- `README.md` with full commands and conversion snippets

Commands to run locally (copy/paste into the project root)

# 1) Create the full project (if you haven't already created it with create-expo-app)
npx create-expo-app@latest thermalcamera --template expo-template-blank-typescript

# or if you already have this scaffold: install deps
## CrossPlatformApps — quick guide

This repository contains several Expo app projects in `apps/` and helper tooling in `scripts/` and `tools/` to scaffold, prebuild, and build native Android (locally) and iOS (on a remote mac via SSH).

Goal of the tools
- Provide a small, repeatable flow to create an Expo TypeScript app, generate native projects (`expo prebuild`), build Android locally, and build iOS on a mac with Xcode via SSH.

Where things live
- apps/ — generated and existing app projects (each app has its own folder, e.g. `thermal_camera/`).
- scripts/ — convenience shell scripts (create project, autoplay, build iOS on mac, ssh wrapper, collect artifacts, cleanup).
- tools/create_expo — small helper records and a README for the create-expo flow.

How to start (recommended short path)
1) From repo root, run the interactive helper to scaffold a new Expo project:

```bash
./scripts/create_expo_project.sh
```

This script prompts for slug, display name, android package id and iOS bundle id, runs `npx create-expo-app --template expo-template-blank-typescript`, updates `app.json`, installs deps and (optionally) runs `npx expo prebuild --platform all`.

2) Build Android locally (after `expo prebuild` has created `android/`):

```bash
cd apps/<your-app>/android
./gradlew assembleDebug -x lint
# artifact: android/app/build/outputs/apk/debug/app-debug.apk
```

3) Build iOS on a mac via SSH

Prepare a mac with Xcode & CocoaPods. From the Linux host you can trigger the mac-side build wrapper:

```bash
./scripts/build_ios_via_ssh.sh user@mac-host /path/on/mac/to/project
```

On the mac the script `scripts/ios_build_on_mac.sh` runs:
- npm install
- npx expo prebuild --platform ios
- cd ios && pod install --repo-update
- xcodebuild (simulator or archive as requested)

Helper scripts
- `scripts/create_expo_project.sh` — interactive scaffold + optional prebuild.
- `scripts/autoplay.sh` — non-interactive orchestrator: scaffold, install, prebuild, build Android, and optionally trigger iOS build on remote mac.
- `scripts/ios_build_on_mac.sh` — run on mac to install pods and xcodebuild.
- `scripts/build_ios_via_ssh.sh` — wrapper to SSH into mac and run the above.
- `scripts/collect_ios_artifacts.sh` — fetch a built .app/.ipa from the mac back to this repo's `artifacts/` if needed.

Notes, edge-cases and tips
- The Java package / bundle ids you supply must match `expo prebuild` output; if you convert Android MainActivity to Kotlin, update the package path in the file location.
- Xcode will create a Bridging Header when you add the first Swift file — accept it to enable Swift.
- Remote mac must have the same Node / Ruby / CocoaPods / Xcode compatibility. If builds fail, check CocoaPods and Xcode versions on the mac.
- If SSH sessions drop during long builds, use `screen`/`tmux` on the mac or run the mac-side build in background and tail logs.

If you'd like, I can now:
- scaffold a new app here in `apps/` (I will run the helper scripts), or
- prepare an updated, small `README` in `tools/create_expo` and `scripts/` (I will do this now), or
- run a dry-run `npx expo prebuild` for an existing app to show generated paths (requires running commands).

Requirements coverage
- Unify README instructions across tools: Done (this file now centralizes the recommended flow).
- Explain how to start: Done (section "How to start").
