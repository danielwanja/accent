# Accent — Product & Technical Plan

A private dialect coach in your pocket. On-device speech analysis (Apple Intelligence),
word-by-word live feedback while you read, and personalized training sessions —
built first for a French-speaking Genevan who has spent 20 years in the US, and
architected so any accent pair works (the "Hollywood dialect coach" generalization).

---

## 1. Vision

Professional dialect coaches work in a loop: **hear it → see it → feel it → drill it → retest**.
Accent packages that loop into a quiet, elegant iOS app:

- **Everything on-device.** Speech never leaves the phone. Privacy is a feature, and it's
  what makes the "A-list actor prepping a role" positioning credible — no studio script
  or celebrity voice sample ever touches a server.
- **The text is the interface.** No mascots, no gems, no streaks-with-confetti. A beautiful
  reading surface that lights up word by word as you speak, and marks — subtly — where
  your pronunciation drifted.
- **A coach, not a grader.** Every flagged word can explain *why* it was flagged, show the
  mouth mechanics, play a reference, and generate a drill on the spot.

**Primary persona (v1):** francophone English speaker, fluent, long-time US resident,
wants to polish specific residual accent features.
**Second persona (v2+):** actor/speaker acquiring a *target* accent (General American → RP,
Southern, etc.). Same engine, different reference model + lexicon.

---

## 2. The core interaction

The reading screen is the product. Large serif text, teleprompter-calm:

1. User picks a passage (curated, pasted, or AI-generated to target their weak phonemes).
2. They tap record and read. The **current word is highlighted in sync** with their voice
   (karaoke-style, driven by live transcription timestamps).
3. As each word is finished it settles into a score state:
   - **ink** — clean
   - **amber underline** — noticeably accented / low confidence
   - **red underline** — mispronounced, omitted, or substituted
4. Tapping a flagged word opens a detail card: expected vs detected phonemes, your audio
   vs a native reference (A/B scrubber), articulation tip ("tongue between the teeth,
   air, no voice — /θ/ is not /s/"), and a one-tap "drill this" button.

---

## 3. Speech pipeline — what Apple gives us, what we build

### 3.1 Live transcription & word timing (Apple, iOS 26)

- `SpeechAnalyzer` + `SpeechTranscriber` (Speech framework, iOS 26): streaming on-device
  transcription with **volatile (partial) results** and `audioTimeRange` attributes on
  each run of the attributed transcript → this drives the karaoke highlight.
- `AVAudioEngine` input tap → `AnalyzerInput` buffers; also record to file for replay/AB.
- Fallback: `SFSpeechRecognizer` (`requiresOnDeviceRecognition = true`) exposes
  **per-word confidence** via `SFTranscriptionSegment` — useful where the new API's
  confidence signals are thin.

### 3.2 Alignment (we build)

The recognizer outputs a hypothesis; the passage is the target. We align them:

- Token-level alignment (Needleman–Wunsch / weighted edit distance over normalized
  tokens, with number/contraction normalization).
- Produces per-word verdicts: **match / substitution / omission / insertion**, plus
  timing per word.
- This alignment layer is also what keeps the highlight honest when the user skips or
  stumbles — resync instead of drifting.

### 3.3 Pronunciation scoring — three tiers

ASR alone is *too forgiving*: it's trained to understand accents, so "zis" often
transcribes as "this". We layer signals:

| Tier | Signal | Ships in |
|------|--------|----------|
| 1. Word | alignment verdict + ASR word confidence (correct word + low confidence ≈ accented) + timing anomalies | M1 |
| 2. Phoneme | on-device Core ML phoneme recognizer (wav2vec2-style CTC, ported to Core ML) + forced alignment against expected phonemes (CMUdict lexicon) → **GOP (Goodness of Pronunciation) score per phoneme** | M3 |
| 3. Prosody | pitch contour (autocorrelation/YIN via Accelerate), syllable stress placement, rhythm/rate vs reference | M3 |

Tier 2 is the moat — it's how ELSA/Speechace-class products score, but ours runs
entirely on-device. Model candidates: wav2vec2-base phoneme checkpoint distilled +
quantized for ANE; target < 80 MB, < 300 ms per utterance chunk.

### 3.4 Reference audio

- `AVSpeechSynthesizer` with premium/enhanced voices for instant per-word and
  per-sentence native reference (slow mode = rate 0.35).
- Word-level A/B: user's slice (from timestamps) vs synthesized reference.

### 3.5 Coaching intelligence (Apple, FoundationModels)

`FoundationModels` framework (on-device Apple Intelligence LLM, iOS 26):

- Generate practice sentences saturated with the user's weak phonemes
  (`@Generable` structured output → typed drill objects, validated against lexicon).
- Explain errors in plain language, aware of L1: "French has no /h/ phoneme, so…"
- Compose each day's session plan from the issue profile (adaptive difficulty).
- Session summaries ("Today /θ/ hit 82%, up from 64%").

---

## 4. French → American English issue map (seed knowledge base)

Static, curated taxonomy the scorer and coach draw from (each entry: phoneme(s),
L1 interference explanation, articulation cue, minimal pairs, drill templates):

1. **TH** /θ/→[s,t], /ð/→[z,d] — *think/sink, this/zis*
2. **H** dropping + hypercorrection — *air/hair, old/hold*
3. **/ɪ/ vs /iː/** — *ship/sheep, live/leave*
4. **R** uvular [ʁ] → retroflex [ɹ]
5. **Lexical stress** — French pushes stress to final syllable; English is lexical
   (*deVELopment*, not *developMENT*) + schwa reduction
6. **-ed endings** — /t/ vs /d/ vs /ɪd/ (*walked, played, wanted*)
7. **/tʃ/ vs /ʃ/, /dʒ/ vs /ʒ/** — *chair/share, joke/[ʒ]oke*
8. **Vowel space** — /æ/ vs /ɛ/ (*bad/bed*), /ʌ/, diphthongs /oʊ/ /eɪ/ kept pure
9. **Final consonant clusters** — *months, asked*
10. **Linking & silent letters** — *comb, receipt*; French even-rhythm vs English stress-timing

---

## 5. Training session anatomy (5–10 min)

1. **Warm-up** — listen & shadow 2 reference lines (no scoring).
2. **Ear training** — minimal-pair tap test (*ship or sheep?*) — discrimination precedes production.
3. **Articulation drill** — isolated words for today's target phoneme, with mouth-position
   guidance and instant per-word score.
4. **Sentence reading** — live-highlighted passage loaded with the target phoneme.
5. **Retest** — the words missed in the diagnostic/previous session.
6. **Summary** — per-phoneme delta, one insight, tomorrow's focus.

Onboarding = a 2-minute **diagnostic**: read one calibrated passage covering the full
issue map → initial issue profile → first session plan.

---

## 6. Screens (v1)

1. **Today** — single card: today's session + issue-profile ring (per-phoneme mastery).
2. **Read** — the teleprompter surface (core screen). Sources: curated passages,
   paste-your-own, AI-generated.
3. **Word detail** — sheet: phonemes, A/B audio, tip, "drill this".
4. **Progress** — per-phoneme trendlines (Swift Charts), session history, recordings.
5. **Diagnostic** — onboarding flow.

Design language: quiet, editorial, type-forward. Reading face with full IPA coverage
(e.g. Gentium-class serif) for passages and phoneme display; monochrome UI with one
accent; haptic tick on word-advance; recording state = a thin pulsing waveform, not a
big red circle.

---

## 7. Architecture

- **Swift 6 / SwiftUI**, iOS 26 minimum (SpeechAnalyzer + FoundationModels; Apple
  Intelligence devices: iPhone 15 Pro and later).
- Modules (SPM targets):
  - `AudioEngine` — capture, files, playback, levels
  - `Transcription` — SpeechAnalyzer/SFSpeech wrappers → `TimedWord` stream
  - `Alignment` — target↔hypothesis alignment, verdicts
  - `Phonics` — lexicon (CMUdict), G2P fallback, issue taxonomy
  - `Scoring` — tier 1 now, tier 2/3 behind protocol (`PronunciationScorer`)
  - `Coach` — FoundationModels session planning & generation
  - `Store` — SwiftData: profile, sessions, per-phoneme stats, recordings
- No backend, no accounts. iCloud sync via SwiftData/CloudKit later.

---

## 8. Milestones

- **M0 — Proof of magic (1–2 wks):** record → live word-synced highlighting on a fixed
  sentence + word-level match/miss coloring. If this feels great, everything else follows.
  ✅ *Done (Aug 2026): verified in the iOS 26 simulator. Note: SpeechAnalyzer models are
  unavailable in the simulator, so the app falls back to SFSpeechRecognizer there; the
  analyzer path needs a real-device pass.*
- **M1 — Reading engine (2–3 wks):** any text, alignment + tier-1 scoring, word detail
  card with A/B reference audio, recordings saved.
  ✅ *Done (Aug 2026): curated passages + paste-your-own, amber "accented" tier from
  ASR word confidence (<45%), word detail card with native/slow/your-take audio,
  takes recorded to Documents/Recordings. Verified in sim and on device.*
- **M2 — The coach (3–4 wks):** diagnostic, issue profile, FoundationModels-generated
  drills & session flow, Today + Progress screens.
  ✅ *Done (Aug 2026): Phonics issue taxonomy + spelling-heuristic word→issue mapping
  (CMUdict upgrade deferred to M3), SwiftData take store, per-issue mastery profile,
  diagnostic passage, Today (focus card + practice/diagnostic) and Progress (mastery
  bars, clean-rate trend, history). Coach drills use FoundationModels on device with
  curated fallback drills elsewhere — the LLM path compiles but still needs a
  real-device pass. Ear-training minimal-pair tap test deferred to M4 polish.*
- **M3 — Phoneme engine (4–6 wks, parallelizable):** Core ML phoneme model + GOP,
  per-phoneme feedback replaces heuristics, prosody/stress scoring.
  ✅ *Done (Aug 2026): wav2vec2-base phoneme CTC → Core ML fp16 (189 MB — int8
  rejected: it erases the subtle GOP margins; distill/palettize later against a
  real eval set), whole-take forced alignment (own word boundaries at 20 ms + GOP
  without window bleed), GOP bands calibrated on a synthesized substitution
  battery (tools/calibrate.swift; /h/ marked unjudgeable), lexical stress
  detection from per-syllable prominence (energy × duration) vs CMUdict stress.
  Pitch-contour prosody (YIN) deferred — stress placement was the francophone
  priority. Ear training (minimal-pair tap test, §5.2) shipped alongside.*
- **M4 — Polish & ship:** haptics/sound design, accessibility (critical: this is a
  speech app), App Store, TestFlight cohort of francophone friends.

---

## 9. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| ASR normalizes accents → misses errors | Confidence signals in M1; phoneme GOP in M3 is the real fix |
| SpeechTranscriber confidence exposure is limited | Dual-run with SFSpeechRecognizer for segment confidence |
| Phoneme model size/latency on ANE | Quantize + distill; score per-sentence (post-hoc), not per-frame |
| Highlight desync on stumbles/skips | Alignment layer resyncs on anchor words; volatile-result smoothing |
| iOS 26 / device floor excludes older phones | Accepted for v1 — the APIs are the product |
| Over-flagging discourages users | Calibrated thresholds; show at most top-N issues per session; tone: coach, not judge |

---

## 10. Success criteria

- Highlight latency ≤ ~300 ms behind the voice; zero desync on clean reads.
- Diagnostic reliably surfaces the classic French issue set on a known-accent speaker.
- 4-week self-test: measurable GOP improvement on 3 target phonemes.
- The reading screen is something you'd happily show on stage — that's the bar.
