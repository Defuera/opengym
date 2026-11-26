# ADR-040: One Reply for Quick Messages

Status: Accepted

## Context

Read from live traces on 2026-11-26: the person sent a photo with the text "See attached." and seconds later the real question. Two coach turns ran. The first guessed and tied the photo to an earlier topic. The second answered well, but its place update was rejected with "no photo in this turn", because the photo belonged to the first message.

## Decision

- One coach turn answers all messages of the person since the last assistant message, with all their files.
- When a turn starts and a newer message of the person exists in the thread, the older turn stays silent and gives its pending count back. A voice message without a transcript and a tap on "approve" that plain code answered do not count as newer.
- The files of the earlier unanswered messages count as attached to the turn (`attachedToThisMessage`, and the photo evidence of `update_place`).
- A message with files and under 25 characters of text starts its turn 2.5 seconds late, so a follow-up text can arrive. Other messages start at once.
- The prompt says: a photo or file with no question gets one line on what it shows and a question on what to do with it.

## Consequences

- A turn that already runs when the next message arrives still answers alone; the window is small and is not closed.
- A photo-only message waits 2.5 seconds before the coach starts.
