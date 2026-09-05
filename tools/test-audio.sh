#!/bin/zsh
# Synthetic smoke test; this is not validation on human native/French speakers.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/accent-audio-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
cp Accent/cmudict.txt "$TEST_DIR/cmudict.txt"
xcrun swiftc -O -target arm64-apple-macos26.0 -module-cache-path "$TEST_DIR/cache" \
  Accent/Passage.swift Accent/TimedWord.swift Accent/PhonemeScorer.swift \
  Accent/Lexicon.swift Accent/Phonics.swift tools/audio-regression.swift -o "$TEST_DIR/audio-regression"
"$TEST_DIR/audio-regression" "$TEST_DIR"
