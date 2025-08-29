Autoplay orchestration

`scripts/autoplay.sh` is a convenience orchestrator that can:
- scaffold a new Expo TypeScript project,
- update `app.json` and install deps,
- run `npx expo prebuild --platform all`,
- build Android locally, and
- optionally trigger a remote iOS build on a mac via SSH.

Examples

- Interactive full run:

```bash
./scripts/autoplay.sh
```

- Non-interactive with defaults, skip remote iOS:

```bash
./scripts/autoplay.sh --slug myapp --name "My App" --android-pkg com.example.myapp --ios-bundle com.example.myapp --yes --no-ios
```

- Trigger remote iOS build (requires SSH access and `scripts/build_ios_via_ssh.sh`):

```bash
./scripts/autoplay.sh --slug myapp --remote user@mac-host --remote-path /path/on/mac
```

Notes

- The script assumes `npx create-expo-app` and `npx expo` are available.
- Remote iOS builds require a mac with Xcode and CocoaPods; device or archive builds additionally require code signing credentials on the mac.
