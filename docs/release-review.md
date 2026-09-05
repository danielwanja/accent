# Source release review — September 5, 2026

The repository remains private at the owner's request. The source is prepared
for a later public release; no App Store binary is published by this work.

## Confidential data checks

- Gitleaks 8.30.1 scanned all 28 existing commits with `--log-opts=--all` and
  redacted output: no secrets found. The official macOS ARM64 download was
  checked against its published SHA-256 checksum.
- Gitleaks also scanned a snapshot of tracked and unignored working files:
  no secrets found. Ignored model weights, local build products, and logs are
  outside the source release.
- Reviewed the historical file inventory: no committed human recordings,
  databases, environment files, private keys, or signing certificates found.
- Removed the personal development-team setting and local calibration path
  from the current files; replaced the personal simulator UUID in `run.sh`.
- Git author metadata and old nonsecret team/path/simulator identifiers remain
  in history. `PLAN.md` is deleted at the current revision and remains in old
  commits. History has not been rewritten.
- Extended ignore rules for credentials, signing material, recordings,
  databases, and diagnostic output.

Secret scanning is a best-effort check, not proof that every possible sensitive
value is absent. Repeat the checks before any later public release.

## Privacy and attribution

- Legacy speech recognition now explicitly requires on-device support; it
  fails instead of falling back to server recognition.
- Transcript/reference text diagnostics are restricted to DEBUG builds.
- Added privacy documentation, MIT licensing for original work, CMUdict's
  redistribution notice, and CC BY 4.0 attribution for MultiBridge model labels
  and optional converted weights. A copy of the third-party notice is bundled
  with the app.
- Documentation screenshots use an in-memory DEBUG fixture with no microphone
  or personal history. Illustrative scores are disclosed in README and article.

## Verification

- Five simulator UI tests pass on iOS 26.2 after the release-preparation changes.
- A clean source snapshot builds in Release for the iOS simulator with no model
  weights and no personal signing configuration.
- The 1024 × 1024 app icon is opaque and compiles into the asset catalog.
- Regression and synthetic-audio suites passed before release preparation;
  this work does not change the acoustic scoring policy.
- The n-so.com article compiles in the website production build. It is a local
  draft; deployment is a separate action.
