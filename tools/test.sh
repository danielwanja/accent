#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/accent-tests.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
cp Accent/cmudict.txt "$TEST_DIR/cmudict.txt"
xcrun swiftc -O -target arm64-apple-macos26.0 -module-cache-path "$TEST_DIR/cache" \
  Accent/Passage.swift Accent/TimedWord.swift Accent/TranscriptBuffer.swift \
  Accent/PhonemeScorer.swift Accent/Lexicon.swift Accent/Phonics.swift Accent/Store.swift \
  tools/regression.swift -o "$TEST_DIR/regression"
"$TEST_DIR/regression"
