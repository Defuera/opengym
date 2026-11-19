# ADR-026: Every Conversation With the Coach Is the Chat

## Status

Accepted (details Proposed)

## Date

2026-11-19

## Context

The person talks to the coach in several places that work differently: the chat (text, voice, images, files), a "New program" text screen, the session start sheet, and "Change plan" on a session. Each has its own screen and its own way of showing what the coach offers. The owner decided on 2026-11-19 that every place where the person talks to the coach is the same chat interface, and that a program is made and changed there. ADR-025 already planned that a thread says what it is about and that the coach answers with text plus optional proposals.

## Decision

- Every conversation with the coach is the chat. It is one interface: text, voice, images and files.
- A thread says what it is about (`threads.about`). A thread about a program is opened from the program, or from "New program". It is reused: at most one thread per program, and one new-program thread that has no agreed proposal.
- The coach acts through proposals shown in the chat. The coach reply in such a thread is JSON `{ text, proposeProgram?: { brief } }`. When `proposeProgram` is set, code creates the proposal (origin `chat`, linked to the thread and the message) and starts the existing `build_program` job. The model only says what to write. There is no provider tool API (ADR-005 holds).
- The proposal shows as a card under the coach message: busy, or the program with Agree and Cancel, or the result. Feedback is the next message. A new proposal replaces the open one.
- A thread that is about something is hidden from the chat list by default. "Show all chats" shows it.
- Nothing is written silently from a pasted program: in such a thread the notes and goals job and the title job do not run.

## Done in this step

Programs only: `about` on threads, `proposalId` on messages, `threadId` and `messageId` on proposals, the job `chat_program`, `queries/proposals:forThread`, the files of the chat reaching `build_program`, and the removal of the thread with its program. The contract is in `docs/api-contract.md`, "Chat about a program".

## Not done yet

- Session start, "Change plan" on a session and "Something else" in the start sheet still use their own screens and start requests.
- The chat inside a running session does not exist yet.
- `threads.placeId` has not moved into `about`.
- `commands/proposals:request`, `queries/proposals:get` and `queries/proposals:open` are still there (the installed app uses them) and are removed later, with the app's "New program" screen.
- The notes and goals job has not folded into the chat reply.

## Consequences

- One way to ask the coach for something. The program step reuses the proposal block (ADR-025); no second mechanism.
- Two extra reads per program reply: the chat context (as `chat`) and a small query for the program state. A program build reads the files of the thread, newest 6.
- A proposal that nobody applies is deleted after 7 days; a message then shows no card.
- Not verified: how the reply and the build behave with a real provider and a long pasted program. The tests use the mock and a stubbed provider.
