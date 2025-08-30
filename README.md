
Checklist
- Create an Expo app scaffold (TypeScript)
- Generate native projects and convert Android to Kotlin and iOS to Swift
- Build & verify Android locally with Android Studio
- Build & verify iOS remotely over SSH (Xcode machine)

Quick plan
# CrossPlatformApps — automation & build helpers

This repository contains Expo apps under `apps/` and a small set of helper scripts in `scripts/` that automate creating an Expo TypeScript project, generating native projects (`expo prebuild`), building Android locally, and building iOS on a remote mac via SSH.

This README documents the automation flow, the key scripts, expected inputs/outputs, environment prerequisites, common flags, artifact locations, and debugging tips. The goal is to make the flow machine- and LLM-friendly so an automated agent can reason about and run the steps.

## High-level flow
- Create or reuse an Expo TypeScript app under `apps/<slug>`.
- Install JS dependencies and run `npx expo prebuild --platform all` to generate `android/` and `ios/`.
- Build Android locally via Gradle (requires Android SDK).
- Rsync the app to a mac and run a per-app remote helper (`remote_ios_build.sh`) on the mac to `pod install` and run `xcodebuild` (simulator or archive). Fetch artifacts back to `artifacts/<slug>/`.

## Important locations
- apps/ — per-app project folders (one folder per app slug).
- scripts/ — automation scripts. A canonical per-app remote helper lives at `scripts/remote_ios_build.sh` and is copied into apps at creation time.
- artifacts/<slug>/ — build outputs fetched from remote mac and local builds (APK, simulator ZIPs, etc.).

## Key scripts (summary)
- `scripts/create_expo_project.sh` — interactive creator for a single app. Prompts for slug, app name, Android package and iOS bundle id. Copies `scripts/remote_ios_build.sh` into the created app.
- `scripts/autoplay.sh` — non-interactive orchestrator. Supports creating an app (unless `apps/<slug>` already exists), installing deps, prebuilding, building Android locally, rsync'ing to a remote mac, triggering remote iOS build, and fetching artifacts. Designed for CI or automated flows.
- `scripts/remote_ios_build.sh` — canonical per-app remote helper. This script is copied to `apps/<slug>/remote_ios_build.sh` during creation. It installs JS deps, runs `expo prebuild --platform ios`, optionally runs `pod install`, runs `xcodebuild` (workspace or project detection), and zips simulator `.app` into `artifacts/ios/<slug>-simulator.zip`.
- `scripts/build_ios_via_ssh.sh` & `scripts/ios_build_on_mac.sh` — older/alternate helpers to run iOS builds on a remote mac (kept for compatibility).
- `scripts/collect_ios_artifacts.sh` — convenience to rsync artifacts from a remote mac to the local `artifacts/` folder.

## Script inputs, outputs, and flags

- `scripts/autoplay.sh` (common flags):
	- --slug SLUG (default: myapp) — app folder name under `apps/`.
	- --name NAME — app display name.
	- --android-pkg PKG — Android package id (reverse DNS).
	- --ios-bundle BUNDLE — iOS bundle id (reverse DNS).
	- --no-android — skip Android local build.
	- --no-ios — skip remote iOS build.
	- --no-pod | --skip-pod — forwarded to remote helper to skip CocoaPods `pod install` (fast iterative builds).
	- --remote user@host — SSH target for remote build (default: praveenojha@192.168.2.18).
	- --remote-path /path/on/mac — remote directory for the project (default: /Users/<user>/Desktop/<slug>).
	- --cleanup — remove local and remote build caches for the given slug.
	- --yes — non-interactive (accept defaults).

Inputs: app source under `apps/<slug>` (created if missing). Outputs: APK copied to `artifacts/<slug>/` (if Android build), iOS simulator zip copied to `artifacts/<slug>/ios/` after successful remote run.

## Environment prerequisites
- Local Linux machine (this repo) needs: Node.js, npm, expo CLI (installed on demand via npx). For Android builds, an Android SDK must be available and reachable via `ANDROID_SDK_ROOT` or common paths such as `$HOME/Android/Sdk` or `/home/praveen/Work/Android/sdk`.
- Remote mac needs: Xcode, CocoaPods, Node.js, npm, and the usual homebrew paths. Non-interactive SSH shells on macs often miss PATH and locale; the canonical `scripts/remote_ios_build.sh` exports PATH and LANG/LC_ALL to mitigate this.

## Per-script behavior details (for an LLM)

- create_expo_project.sh
	- Prompts for metadata and runs `npx create-expo-app "apps/<slug>" -t expo-template-blank-typescript`.
	- Updates `app.json` with the supplied name/slug/package ids using a small Node.js one-liner.
	- Optionally runs `npm install` and `npx expo prebuild --platform all`.
	- Copies `scripts/remote_ios_build.sh` into the created app so the remote helper is always present in the app folder.

- autoplay.sh
	- Non-interactive orchestrator suitable for CI or automated agents.
	- If `apps/<slug>` already exists it will NOT recreate the project; it will cd into that folder and continue (install, prebuild, build).
	- Installs JS deps (`npm install`), runs `npx expo prebuild --platform all` to ensure `android/` and `ios/` exist.
	- Detects Android SDK in several common locations and writes `android/local.properties` when possible so Gradle can find the SDK.
	- Runs `./gradlew assembleDebug -x lint` under `apps/<slug>/android` to produce a debug APK and copies it to `artifacts/<slug>/`.
	- Rsyncs the project to the remote mac and runs the per-app `remote_ios_build.sh` there using `ssh 'bash -lc'` to get a login-like shell (helps find Homebrew-installed binaries). If `--skip-pod` is passed, it will skip `pod install` on the mac.
	- Fetches `artifacts/ios/` from the remote and stores them under local `artifacts/<slug>/ios/`.

- scripts/remote_ios_build.sh (canonical)
	- Export PATH to include `/opt/homebrew/bin:/usr/local/bin` and export UTF-8 locale values for LANG and LC_ALL.
	- Installs JS deps (`npm ci` if package-lock.json present, otherwise `npm install`).
	- Runs `npx expo prebuild --platform ios` to ensure the iOS project is present.
	- Optionally runs `LANG=... LC_ALL=... pod install --repo-update` inside `ios/` unless `--skip-pod` was supplied.
	- Detects `.xcworkspace` or `.xcodeproj` directories using `find -type d` (directory-based detection to avoid matching files like `contents.xcworkspacedata`).
	- Runs `xcodebuild` with `-sdk iphonesimulator` into a `ios-build` derived data path to create a simulator `.app`.
	- Zips the built `.app` into `artifacts/ios/<slug>-simulator.zip` so it can be rsynced back to the Linux host.

## Common failure modes and debugging hints
- Android Gradle cannot find SDK: ensure ANDROID_SDK_ROOT or ANDROID_HOME is set, or place SDK at `$HOME/Android/Sdk` or `/home/praveen/Work/Android/sdk`. The scripts will attempt to write `android/local.properties` when they detect the SDK.
- CocoaPods encoding errors under SSH: often caused by missing UTF-8 locale; the helper exports LANG/LC_ALL and runs `pod install` with those env vars.
- xcodebuild cannot find workspace/project: older scripts used basename parsing and sometimes matched inner files; the canonical helper uses directory-based `find` to locate `.xcworkspace` and `.xcodeproj` directories.
- Remote PATH differences: Homebrew-installed `pod`, `node`, or `npm` may not be on PATH for non-interactive SSH. The helper prepends common Homebrew locations to PATH and runs commands under `bash -lc` on the remote.

## Example commands

- Create or update and build both platforms (default remote):
```bash
./scripts/autoplay.sh --slug animalvision --name "AnimalVision" \
	--android-pkg ilabs.animalvision --ios-bundle ilabs.animalvision --yes
```

- Create but skip remote iOS build (local only):
```bash
./scripts/autoplay.sh --slug animalvision --name "AnimalVision" --no-ios --yes
```

- Run remote iOS build only (assumes app already exists locally):
```bash
./scripts/autoplay.sh --slug animalvision --no-android --yes
```

## For an LLM to reason about the flow
- The automation is deterministic: inputs are the CLI flags and the contents of `apps/<slug>`.
- The main mutation points are `app.json` updates and generated native folders under `apps/<slug>/android` and `apps/<slug>/ios`.
- Key side-effects to watch for:
	- Files written: `apps/<slug>/android/local.properties`, `apps/<slug>/remote_ios_build.sh` (copied), `artifacts/<slug>/*` (build outputs).
	- Remote side-effects when running iOS builds: files under the remote `$REMOTE_PATH` (rsynced project and remote `artifacts/`).

## Next steps you can automate (suggestions)
- Add verbose remote logging: have `remote_ios_build.sh` tee `xcodebuild` and `pod` output into `artifacts/` so the logs are fetched back.
- Add `--skip-npm` or `--no-npm` flags to speed iterative builds when JS deps haven't changed.
- Add a CI job to run `./scripts/autoplay.sh --slug <ci-app> --no-ios --yes` to validate Android builds in CI.

## Contact & maintenance notes
- The canonical per-app remote helper is `scripts/remote_ios_build.sh`. Edit this file to change remote build behavior; newly created apps will receive a copy. If you edit per-app copies, prefer applying the change to the canonical script and re-copying.

If you want, I can now:
- Add remote log capture (tee) to `scripts/remote_ios_build.sh` and update `autoplay.sh` to fetch logs.
- Add `--skip-npm` to speed iteration.
- Run the full build for `animalvision` now (I will attempt local Gradle and remote SSH).
