#!/bin/bash
# Run Accent's command-line and simulator tests from any working directory.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./test.sh [--quick | --audio | --ui] [--destination DESTINATION]

With no suite option, runs regression, synthetic-audio, and simulator UI tests.
  --quick       Run only the fast regression tests (no simulator).
  --audio       Run only the synthetic-audio tests (no microphone).
  --ui          Build the app and run the simulator UI tests.
  --destination Override the Xcode simulator destination.
  -h, --help    Show this help.

Requires an Apple Silicon Mac and Xcode 27 or later. Audio tests also need
tools/models/PhonemeRecognizer.mlpackage and the Samantha English voice.
Uses DEVELOPER_DIR if set, otherwise prefers /Applications/Xcode-beta.app.
The default simulator is iPhone 17 Pro on iOS 26.2, matching run.sh.
Set SIM_UDID to use a particular simulator, or pass --destination, for example:
  ./test.sh --ui --destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
EOF
}

suite=all
destination="platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2"
if [[ -n "${SIM_UDID:-}" ]]; then
  destination="platform=iOS Simulator,id=$SIM_UDID"
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick|--audio|--ui)
      if [[ "$suite" != all ]]; then
        echo "Choose just one suite option, or omit it to run all tests." >&2
        exit 2
      fi
      suite="${1#--}"
      shift
      ;;
    --destination)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "--destination requires an Xcode simulator destination." >&2
        exit 2
      fi
      destination="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

if [[ "$suite" == all || "$suite" == audio ]]; then
  if [[ ! -d tools/models/PhonemeRecognizer.mlpackage ]]; then
    echo "Missing tools/models/PhonemeRecognizer.mlpackage. Generate it with tools/convert.py." >&2
    echo "Use ./test.sh --quick to run the regression tests without the model." >&2
    exit 1
  fi
fi

if [[ "$suite" == all || "$suite" == quick ]]; then
  echo "▸ Running regression tests…"
  /bin/zsh tools/test.sh
fi

if [[ "$suite" == all || "$suite" == audio ]]; then
  echo "▸ Running synthetic-audio tests…"
  /bin/zsh tools/test-audio.sh
fi

if [[ "$suite" == all || "$suite" == ui ]]; then
  mkdir -p build/test-results
  result_dir=$(mktemp -d "$PWD/build/test-results/run.XXXXXX")
  echo "▸ Running simulator UI tests on ${destination}…"
  echo "  Build and test log: $result_dir/xcodebuild.log"
  if ! xcodebuild -project Accent.xcodeproj -scheme Accent \
    -destination "$destination" -destination-timeout 60 \
    -derivedDataPath build -parallel-testing-enabled NO \
    -resultBundlePath "$result_dir/Tests.xcresult" \
    test > "$result_dir/xcodebuild.log" 2>&1; then
    tail -n 80 "$result_dir/xcodebuild.log" >&2
    echo "UI tests failed. Full log: $result_dir/xcodebuild.log" >&2
    exit 1
  fi
  tail -n 15 "$result_dir/xcodebuild.log"
  echo "  Test results: $result_dir/Tests.xcresult"
fi

echo "✓ All requested tests passed."
