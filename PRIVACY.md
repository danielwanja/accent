# Privacy

Accent has no account system, analytics SDK, advertising, or app-operated backend.

- Microphone audio is processed by Apple's on-device Speech APIs. The legacy
  fallback requires local recognition and fails if it is unavailable.
- The optional Core ML phoneme model runs locally after recording.
- Apple Intelligence passage generation uses the default on-device system model.
  Its prompt contains the selected sound and a general practice instruction,
  not the recording or personal practice history.
- Audio clips are stored in the app's Documents/Recordings folder. Take history
  and word results are stored locally using SwiftData. The app does not configure
  CloudKit sync. OS backups may include this data according to device settings.
- Apple may download speech assets, voices, and Apple Intelligence models.
  The developer setup script downloads model weights from Hugging Face.
- Debug builds can log transcript snippets and reference text. Treat development
  logs and simulator result bundles as potentially personal data.

Microphone permission is required to record. The legacy Speech API also requests
speech-recognition permission. You can revoke permissions in iOS Settings.
Removing the app deletes its local container; separately retained device backups
remain subject to your backup settings. There is currently no in-app delete-all
control.

The repository screenshots use simulator practice content, with no personal
recordings. Please use synthetic examples when reporting bugs.
