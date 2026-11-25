# ADR-037: The Chat Composer Always Works; Messages Wait in the Outbox

## Status

Accepted. Replaces the rule "Chat needs a connection; it is not queued in the outbox" (the app README and the offline line of ADR-032's composer).

## Date

2026-11-25

## Context

The chat composer was switched off when the link was down, and the send button waited while a message was going out. The owner opened the chat, the thread history was still loading, and he could not type. His words: "Open chat, it's loading for some time, so I cannot input my message. It should not work like this. I should always be able to input my message and send, and then you can show loading or like sending if it takes time to send, and it can kind of fail also."

## Decision

- The text field, the attach button, the camera and send are never off because of the connection, a thread that is loading, a message that is going out or a coach reply that is still coming. The mic is off only while a recording is being turned into text. A quiet line replaces the old block: "Offline. Messages are sent when the connection is back."
- Sending is accepted at once. The message shows in the thread and is saved in the outbox on disk (op `chat.send`, the same outbox as the other writes, ADR-003 and ADR-012). The first message of a new chat carries the making of the thread, so a chat opened offline is created when its first message goes out. The files are kept by path and upload when the message goes out.
- The bubble says "Sending…" while the message waits or goes out, and "Not sent" with "Try again" when it did not go out: no link, a failed try, or set aside after five failed tries. A message the server refuses is kept as "Not sent", never dropped. The text and the files stay.
- Messages go out in order. Several can wait. They go out by themselves when the connection is back (the outbox runs on reconnect); "Try again" sends now. The message id is made once and never changes, so the server (`commands/messages:send`, `commands/threads:create`, file upload) stores each thing once.
- Unsent messages survive leaving the chat and restarting the app. A chat whose first message is not on the server yet is listed with the other chats.
- The quick answers under a question (Approve, Change something, Done) queue the same way, with the answer attached.
- Voice: recording works offline. Turning the recording into text needs the server, so it fails with the kept recording and "Try again" ("Offline. The recording is kept. Press Try again when the connection is back.").

## Not changed

Reading threads and messages, the proposal buttons (agree and cancel), renaming and deleting a thread, and the coach model still need a connection and say so.

## Consequences and limits

- Not verified on a device: the behaviour with a real flaky link, and an upload of a large file after a restart (the file must still exist at its path; if it does not, the message stays "Not sent").
- A message that cannot be sent blocks the writes behind it in the outbox until it is set aside (five failed tries). The outbox gives a chat message 90 seconds, other writes 20 seconds.
- A message in a thread that was deleted on the server is refused and stays "Not sent".
