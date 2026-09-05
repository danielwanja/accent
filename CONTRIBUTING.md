# Contributing

Thanks for helping improve Accent. Start with the build instructions in the
[README](README.md), then run `./test.sh --quick` before changing behavior.

Keep pull requests focused and describe the user-visible problem, the resulting
behavior, and how you checked it. Run regression tests for alignment/scoring
changes, audio checks for acoustic changes, and simulator UI tests for sheet or
playback interactions. Verify real microphone behavior on an iPhone when relevant.

Particularly useful contributions:

- Held-out pronunciation evaluation across native and French-accented speakers.
- Fewer false corrections without hiding uncertainty or overstating accuracy.
- Tracking around pauses, restarts, skipped words, and revised transcripts.
- Clearer sound cues, accessibility, and local data-management controls.

Get explicit consent and redistribution rights before contributing any human
recordings. Prefer synthetic fixtures in public issues. Never commit recordings,
API keys, signing material, model weights, local databases, or unredacted logs.
Do not add a server-based speech fallback or analytics without discussing the
privacy implications first.

Contributions to original code and documentation are provided under the project's
MIT license. Preserve all third-party notices for datasets and models.
