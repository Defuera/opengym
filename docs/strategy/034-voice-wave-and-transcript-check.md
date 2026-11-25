# ADR-034: Voice: a Live Wave, and the Transcript Goes to the Text Field

## Status

Accepted

Note: the owner asked for this on 2026-11-25: "Now, when I'm recording voice, can we show a wave function, same as in Claude Code, so I understand that app can hear me? And also, let's place a text before sending transcription, so I can check that it is correct transcription."

## Date

2026-11-25

## Context

A voice message was sent to the server at once. The server turned it into text and started the coach. The person saw a timer while recording, so he could not tell that the app heard him. He could not check the text before the coach answered (R34, ADR-026, ADR-032).

## Decision

- **A live wave while recording.** The recording row shows thin vertical bars that scroll to the left, newest on the right. Silence is a flat low line; speech makes tall bars. The cancel button, the timer and the stop button stay. The level comes from the `record` plugin (`onAmplitudeChanged`, every 80 ms, dBFS). The app maps it to 0..1 with a floor of -50 dBFS (`levelFromDb`). The floor is an inference: speech near a phone sits between about -40 and -10 dBFS (not measured on the owner's phone). The app keeps the last 64 levels.
- **The text goes to the text field, not to the coach.** After stop the app uploads the audio and calls the new action `commands/voice:transcribe`. The text goes into the composer's text field, after a space when the field already holds text. The person reads it, edits it, and sends it with the normal send button as a typed message with the same screen `context` (ADR-032). Nothing goes to the coach before that tap. No message is stored for the recording.
- **While it waits.** The composer shows "Transcribing…" with a cancel button; the mic is off.
- **On failure** (no connection, provider error, no speech) the composer shows a quiet note with "Try again" and a close mark. The recording stays on the phone and on the server, and "Try again" reads the same upload. Cancel, and the close mark, drop everything: the upload is removed, and so is the local file. Starting a new recording also drops a kept one.
- **Server.** `commands/voice:transcribe { token, fileId }` returns `{ ok: true, text }` or `{ ok: false, reason }`. It uses the same core as the voice message job (`lib/transcribe.ts`): provider `transcribe`, trim, cap at 8000 characters. On success it removes the audio (storage blob and `files` row), since no message holds it. A reason is a short reduced text; a provider message never leaves the server.
- **Old flow kept.** `messages:sendVoice`, `messages:retryVoice` and `jobs/voice:transcribe` stay as they are, so an older app build on another phone still works. The app still shows old voice bubbles (mic icon, "Listening…", failed with "Try again"). The new app no longer sends voice messages, so `CoachStore.sendVoice` and the unsent-voice paths were deleted.

## Consequences

- ADR-032 said a voice message carries no screen context. The text from a recording is now a typed message, so it carries the context. For the old flow nothing changes.
- The deploy needs the new function: regenerate `functions/_generated` (`api.d.ts` lists `commands/voice`). An app build with this change, on a server without it, shows the failure note and "Try again".
- No native change: the `record` plugin already gives amplitude, and the microphone permission is the same.
- Cost: one more round trip before the text shows. The wait is shown, and the person is never left unsure whether the app heard him.
- Orphan audio files can stay on the server when the app is killed between upload and answer. This is not cleaned up here (inference: rare, and small files).
