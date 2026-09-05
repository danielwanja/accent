#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python_bin="${PYTHON:-tools/venv/bin/python}"
if [[ ! -x "$python_bin" ]]; then
  echo "Create tools/venv and install tools/requirements-model.txt first; see README.md." >&2
  exit 1
fi
"$python_bin" tools/convert.py
mkdir -p Accent/PhonemeRecognizer.mlpackage
ditto tools/models/PhonemeRecognizer.mlpackage Accent/PhonemeRecognizer.mlpackage
cp tools/models/phoneme_labels.json Accent/phoneme_labels.json
echo "✓ Model and matching labels installed. Rebuild Accent to include sound assessment."
