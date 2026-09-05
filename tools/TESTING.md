# Pronunciation and tracking validation

From the repository root on an Apple Silicon Mac with the Xcode 27 SDK or later
(the app still supports iOS 26 at runtime):

```sh
./test.sh          # Regression, synthetic-audio, and simulator UI tests
./test.sh --quick  # Regression tests only, without a simulator
./test.sh --audio  # Synthetic-audio tests only
./test.sh --ui     # Simulator UI tests only (also builds the app)
```

The script works from any working directory, stops on failure, and returns a
nonzero exit status if a suite fails. It honors `DEVELOPER_DIR`, otherwise prefers
`/Applications/Xcode-beta.app` when installed. UI tests default to iPhone 17 Pro
on iOS 26.2, matching `run.sh`. Set `SIM_UDID` or pass `--destination` to
choose another simulator:

```sh
./test.sh --ui --destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
```

UI build logs and Xcode result bundles are retained in `build/test-results/`.
Run `./test.sh --help` for all options. The separate audio activation/playback
smoke hook described below remains a manual check.

The audio suite requires the local `tools/models/PhonemeRecognizer.mlpackage`
(regenerate with `tools/convert.py` if missing) and the Samantha English voice.
It synthesizes files locally; it does not record the microphone or upload audio.

## September 5, 2026 results

- Tracking, transcript revisions, split attribute runs, CTC edge cases, feedback
  policy, and saved-history compatibility pass the regression suite.
- The iOS simulator app builds successfully.
- Four diagnostic sentences spoken by Samantha at 120, 180, and 240 words/minute:
  the original scorer flagged **28/138** word occurrences; the revised policy
  flags **7/138**. The original comparison includes its GOP and stress verdicts.
- Deliberate substitutions (`sink/think`, `tank/thank`, `tree/three`, `ship/sheep`,
  `sit/seat`, `bed/bad`) at 140 and 200 words/minute: **7/12 detected**.
- Silence produces no pronunciation correction.

These are development smoke checks on synthesized audio, not an independent
human-speaker evaluation. The settings were adjusted using these examples.
Remaining native flags and missed substitutions are real limitations. The new
policy leaves unreliable sounds, weak function words, and selected heteronyms
unassessed, so the flagged-word count is not a full-coverage accuracy measure.

## What changed

Live alignment ends at the best matching passage prefix, leaving the unread
suffix alone. Analyzer updates replace their audio ranges, including partial
finalizations. Tokenization happens before examining attributed timing runs, so
split graphemes stay inside their word. Shared/overlapping timings are explicitly
estimated. Stopping drains the final transcript before scoring; busy-session
controls and take identifiers prevent late callbacks from changing another take.

Post-read scoring uses bounded chunks of the recognized transcript, preserving
insertions and avoiding forced alignment of skipped passage words. Unknown-word
chunks and implausible boundaries stay unassessed. Posterior peaks avoid averaging
CTC blank frames or making speaking duration an error signal. ASR confidence and
energy-based stress estimates no longer cause pronunciation flags. Incompatible
vowel/consonant comparisons are treated as suspect boundaries. A practice cue
requires acoustic evidence, a competing sound, and a peak log-margin of at most
-3 (about a 20:1 peak ratio, not a calibrated error probability).

Word cards give a target sound, a mouth-position cue, and a repeat-in-context
exercise. A dotted underline means check recognition; amber means a suggested
sound exercise. Recognition counts and sound progress are separate. Older takes
remain readable in history; sound progress uses only the new assessed-evidence
fields, rather than reinterpreting old raw scores.

## Device follow-up

Use held-out recordings from several native English and French speakers, with
normal, slow, and fast readings; pauses, restarts, omissions, and background noise.
Check live cursor movement, final word timestamps, and A/B playback on an iPhone.
Have a human listener label individual sound differences before tuning further.
The automated checks do not establish live microphone accuracy or perceptual
quality across voices and dialects.

## Detail-pane dismissal UI tests

`AccentUITests/WordDetailsUITests.swift` exercises the production detail sheet:
close-button taps, downward drags on the header, downward swipes on the content,
and closing after scrolling. Run through the Accent scheme's Test action, or:

```sh
xcodebuild -project Accent.xcodeproj -scheme Accent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath build -parallel-testing-enabled NO test
```

The DEBUG-only `-testWordDetails` launch argument opens the real sheet without
recording audio, starting the pronunciation model, or creating a sample take.
The detail pane uses a native sheet with medium/large heights, a persistent
navigation-bar close button, and system scroll/dismiss gesture coordination.
Live word haptics run in a cancellable task after a short coalescing delay,
keeping bursty recognition updates out of SwiftUI render callbacks.


## Audio activation and playback smoke test

Launch a DEBUG build with `-audioSmokeTest`. It uses an in-memory take store,
creates a temporary silent clip, cancels pending reference/clip requests, and
then plays two reference/clip pairs through the production audio paths. It does
not access the microphone or saved recordings. The console must include
`ACCENT audio smoke: completed`, two speech starts and two successful clip
completions, without `main thread` activation warnings or a cancelled reference
starting. Run on both iOS 26 (queued synchronous activation) and iOS 27 (the new
asynchronous activation API). Blocking category setup, file reading, player
preparation, and player start/stop are confined to a serial background queue.

`testCloseWhileReferenceStarts` also checks that a detail sheet stays dismissible
when a reference playback request has just been submitted.


Audio-threading verification (September 5, 2026): the playback smoke test
completed on iOS 26.2 and 27.0 simulators with two successful speech/clip pairs,
no cancelled request starting, and no main-thread activation warnings. The
remaining iOS 27 main-thread stall was traced to synchronous speech-voice
lookup; voice discovery now runs in a shared background task as well.
