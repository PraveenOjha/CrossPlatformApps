Create Expo project helper

This folder documents the lightweight helper flow to scaffold a new Expo TypeScript app that fits this repo's conventions.

Quick use

1) From the repository root run the interactive helper:

```bash
./scripts/create_expo_project.sh
```

2) The script will prompt for slug, display name, android package id, and iOS bundle id, then run `npx create-expo-app --template expo-template-blank-typescript`, update `app.json`, install dependencies and optionally run `npx expo prebuild --platform all`.

Where prompts are saved

Saved prompt records (used by the helper) are placed in `tools/create_expo/projects/*.prompt.json`.

If you'd like, I can expand these docs with example prompt JSON and a non-interactive usage example.
