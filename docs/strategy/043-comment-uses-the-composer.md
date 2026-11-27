# ADR-043: The Comment on an Exercise Uses the Same Composer as the Chat, With Photos

## Status

Accepted. Builds step 2 of ADR-029 (photos on the comment) and applies the "one interface" rule to the comment sheet.

Note: the owner asked for this on 2026-11-27, with a screenshot of the exercise "Comment" sheet, which was a plain text field with Save: "As I said before, I want like interfaces to be the same. Here I want to be able for comment also to input a photo, a voice message, like all the same things. We should use same interface everywhere, please." He had said earlier (2026-11-24, in `docs/requirements.md`): "chat must be always the same interface. Always text, image, and photo. It should use the same UI always."

## Date

2026-11-27

## Context

The comment on an exercise (ADR-029) was written in `showTextSheet`: one text field and a Save button. It could not take a photo or a voice note, and it looked different from the chat composer, the note edit form and the import screen, which all use `ComposerBar` (ADR-032, ADR-034, ADR-037).

## Decision

- **One composer.** The comment sheet (title "Comment", question "How did it go?") holds the shared `ComposerBar` with the same controls as the chat: text, camera, the "+" menu (several photos from the library), and voice with the live wave. The voice controller is the same one (`VoiceController`, ADR-034): the transcript goes into the text field and nothing is saved until the person presses the send button, which here has the label "Save". No second composer was built. The wiring is in `lib/screens/comment_sheet.dart`; `lib/widgets` stays standalone.
- **What a comment is.** Text plus zero or more photos. Voice is input only: it becomes text and the audio is not stored on the comment. A comment with photos and no text is a comment.
- **Data.** An optional `commentFileIds` (at most 10 file ids) next to `comment` on an exercise, in the open session and in the finished one, both exercise shapes. The files are the person's own, uploaded with the existing path (`commands/files:generateUploadUrl`, `register`). Every read goes through the user's own file rows (`requireUser`, ADR-039). See `docs/api-contract.md`.
- **Offline (ADR-003).** Saving text never waits for the network: the sheet closes at once and the change goes into the open session and its sync, like every other tap. New photos need a connection, as photos of a note do (the note form says "Offline. Notes need a connection to save."): they upload when the person presses Save. Offline, the "+" and the camera stay on screen but do not work, and a quiet line says so ("Offline. The text is saved now. Photos need a connection."). If an upload fails, the sheet stays open with everything typed and says so. No new queue was made: a photo that is not uploaded is not on the comment. (Inferred: this matches the note form, not the chat, whose outbox keeps files by path; a photo outbox for comments was left out to avoid a second sync path.)
- **Show.** The exercise card shows the comment text and small thumbnails of its photos; a tap on a thumbnail opens the photo large in a sheet (there was no photo viewer in the app, so this is the same sheet the exercise picture uses). The session recap shows the same thumbnails under the comment.
- **Deleting.** Removing a photo from an unsent draft asks nothing. Removing a saved photo asks first (`confirmDelete`). Saving an empty text with no photos removes the saved comment, after `confirmDelete`. A removed saved photo is deleted on the server after the comment is saved (best effort; a failure leaves an unused file).
- **Coach.** The comment text is read as before (ADR-029). The photos of the comment on the exercise in view go to the coach with the request, the same way the photos of the entry in view do, at most 4 images in all and only when the provider takes images. The exercise line carries `commentPhotos: n`. An exercise with photos and no text counts as the person's work, so an outside writer keeps it. No prompt rule was added; one context sentence now says "Photos of the log entry or of the exercise comment the person has open are shown to you."
- **Purge.** The purge of a deleted session (ADR-020) erases the files of its comments.

## Not changed

- The session edit screen still keeps a comment and its photos but does not let the person change them.
- The comment is not shown when the exercise comes again (ADR-029).

## Consequences and limits

- Not verified on a device: the camera and library on a phone, a large photo on a slow link, and the sheet with the keyboard open on a small screen. The tests use fake pickers and a fake client.
- A photo picked while online and saved after the link drops fails the upload and stays in the sheet; the person can save the text by removing the photo.
- Other free-text fields that are not the composer are listed in the report of this change, not here.
