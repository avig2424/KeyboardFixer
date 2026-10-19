#!/bin/bash
# Build and run the converter tests against the real macOS keyboard layouts.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)/kf_tests"
swiftc -framework Carbon -framework AppKit -o "$OUT" \
    Sources/KeyboardConverter.swift Sources/InputSources.swift Sources/Settings.swift \
    Tests/main.swift
"$OUT"
