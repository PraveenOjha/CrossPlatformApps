#!/usr/bin/env bash
set -euo pipefail
echo "Cleaning local build artifacts..."
rm -rf android/.gradle android/app/build android/build ios/build build artifacts/*
echo "Done."
