# ADR-032: One Chat With Functions

## Status

Accepted (step A built: backend; step B built: the app chat; the log draft built in the backend; step D built: goals, limits and notes in the chat; the later steps Proposed)

Note: the owner asked for this in the session of 2026-11-24. A session was open at the place "Gym". The note of one exercise said "No balance board at the gym". That was false: the text of the Gym did not list a balance board, and that text is learned from the log and the chat; it is not a full list. He typed "I do have a balance board" in "Change plan". The coach rebuilt the whole session as a home session (only the place "Home" lists a balance board) and did not update the Gym. His words:

- "it should be the same chat everywhere, and chat is just with functions, and AI knows which functions to call."
- "chat must be always the same interface. Always text, image, and photo. It should use the same UI always."
- "When I open a chat, AI should know what is my current context and what I might want, but then I can report anything, and it can report anything in the app, and then the chat is the same. Super simple."
- "I didn't describe my gym at all. So AI should have known where information is coming from, and this is not a full information."
- "I didn't need to completely change the session. I only needed to fix that one thing."

## Date

2026-11-24

## Context

"Change plan" sent the feedback to `build_session`, which rebuilds the whole session and may choose a place (verified by reading `backend/convex/functions/jobs/startRequest.ts` and `model/ai/jobs/buildSession.ts` on 2026-11-24). Its prompt said "use only equipment that place has". So a place text that did not name an item made the coach move the session to another place. The coach had no way to change one exercise, or to update a place in the same answer.

ADR-026 made every conversation with the coach the chat, with JSON replies and no provider tool API. ADR-028 put the open session on the server, so the coach can change its unfinished part. The design was discussed with the model `gpt-6-astra`; its answer is advice, not the owner's decision.

## Decision

- There is one chat. A message may carry `context`: the screen it was sent from and the ids of what was open (open session, exercise, place, entry, program). The context is a hint. The server reads the real data itself.
- The coach answers one turn with the job `coach_turn`: JSON `{ message, actions: [{ id, name, arguments }], question? }`. It runs through the usual pipeline (`runJob`: prompt, provider, JSON, zod, one retry, plain code fallback, the call stored in `aiCalls`). The actions are a zod union by `name`. An unknown name or bad arguments fail the shape, so the job retries once, then falls back to a fixed message with no action. There is no provider tool API (ADR-005 holds).
- Server code does each action in order, in one transaction, and checks it again against the data now. Each action returns `applied`, `drafted` or `rejected` with a reason. A turn is done once: a second run of the same turn (`turnId` = the user message id) changes nothing. An action id is used once in a turn.
- Every function has a write class:
  - **Applied at once and reported:** `update_place`, `replace_open_exercise`, `add_open_exercise`, `remove_open_exercise`. The coach says in the message what it changed.
  - **Proposal the person approves:** `rebuild_open_session`. A change of the whole session is not written at once. The coach says what it understood and what it proposes; the server checks the plan with the same safety rules, stores it on the message as `proposal` (action status `drafted`) and sets the question with the two answers "Approve" and "Change something". On "approve", plain code applies the plan with no AI call (done sets and comments stay), once; a stale proposal (a newer proposal, another or no open session) is refused with a reason. Any other answer runs a normal coach turn. The owner confirmed this on 2026-11-24 (see requirements.md).
  - **Draft until Done:** facts the coach may suggest (a log entry, a session, a goal, a note, a limit, a program). Nothing is written until the person presses Done. None is built in step A.
  - **Never by AI:** done sets and their numbers, saving a finished session, the person's records and limits, deletes, check-ins, the plan safety limits, and the session's place.
- A comment on one exercise changes that exercise only. `rebuild_open_session` is only for a request to change the whole session, and it is a proposal. When the person does not understand an exercise, the coach explains it in the message and may fix the stored note of that exercise with `replace_open_exercise`. A new exercise image on request is not built: the art pipeline has no safe way to redo one existing image (`lib/exerciseArtDb.ts` skips a name that has art; the delete is an operator function). The person's work (an exercise with a done set or a comment, ADR-029) is never replaced or removed. The plan safety limits and the avoid rules of limits apply to every exercise a function writes (ADR-004, ADR-015). A stale `rev` or another open session refuses the session functions (ADR-028: the phone wins).
- **The place of a session is a fact the person chose.** No function changes it. The coach never chooses or implies another place because a place does not name an item.
- **Place knowledge is partial.** A place text is learned from the person's log and messages. It is never a full list. Equipment that a place does not name is unknown, not missing. Every prompt that holds places says so, per place (`knowledge: "partial" | "unknown"`). The coach writes that something is missing only when the person said so. When the needed equipment is unknown, the chat coach offers the exercise and asks; the session builder gives the exercise and names the fallback in its note ("Balance board if your gym has one; otherwise tandem stand").
- `update_place` is the place exception of ADR-021, now inside the turn. It edits the text from the person's own words in this turn (`evidence: "person_said"`) or a photo attached to this turn (`"seen_in_photo"`), and logs a `placeChanges` row with the evidence and the person's words.

## Built in step A (backend only)

- `commands/messages:send` takes the optional `context` and stores it on the user message. From the screen `session` or `exercise` the coach turn answers (`jobs/coachTurn:run`). Every other message keeps the old chat reply.
- The turn reads what the chat reply reads (`lib/chatInputDb.ts`, `model/coachContext.ts`) plus the open session with exercise ids, done flags and rev, the exercise in view, the session's place, all places, the entry in view and the programs.
- The assistant message holds `turnId`, `actions` (the results) and `question`. `queries/messages:list` returns them.
- `places.knowledgeState?` and `placeChanges.evidence?`. The place rule is in `build_session`, `build_program`, `chat`, `learn_place` and `coach_turn`.
- The old "Change plan" (`commands/start` with feedback, `commands/proposals`) still works.

## Built in step B (mobile app)

- One chat screen and one composer (text, camera, library, file, thumbnails, offline line). The session screen has one floating chat button (owner, 2026-11-24; no "Change plan" chip, no per-exercise action). It opens the chat with `screen: "exercise"` and the id of the exercise on screen, or `screen: "session"` when none is selected. Every send carries the context; a plain chat sends `chat`, a program chat sends `program`.
- A chat opened from a session shows a context line ("Gym, Legs · Tandem Stand") and the hint "What do you want to change?". The thread is reused while the session is open, for the run of the app (not stored on the phone).
- Replies show one plain line per action, an optional whole-workout `proposal` list and a question with quick-answer buttons. A tap sends the label with `answer: { turnId, id }`. The result of an action holds no arguments, so a line names the kind of change ("Changed: one exercise"), not the exercise.
- The old "Change plan" sheet and its rebuild call are gone from the session screen. The Start step still has its own note field.

## Built: the log draft (backend, 2026-11-24)

The owner, 2026-11-23: "There must be no specific routes for such things. What we need is a general log entry and then AI decides what this is: is it nutrition data, is it exercise log that needs to be imported, is it a limitation, whatever it is." And: "let's just have it as really a chat... AI should return a message to me like blah, log created. And then I can either accept it and complete, or I can keep chatting and add more information on the log."

- A message with `context.screen === "log"` runs the coach turn. The log chat is one thread per log. The turn reads every user message and file of the thread (up to 10 files; images only when the provider takes them) and the open draft (`currentLogDraft`). A message may hold only files (its text stays empty).
- The new function `draft_log` is "draft until Done": `{ kind: meal | training | body | goal | other, summary (1..120), at?, session?, goal?, limit?, note? }`. `session` is the import draft shape, `goal` and `limit` are the create shapes (a limit with no id), `note` is `{ text, topic }`. The executor checks each part again with the same zod schemas. A gym exercise with no sets takes the usual sets of the log by the `parse_log` code, or is left out; the model never makes sets up. A part that cannot be written is dropped and the action detail says so.
- The draft is stored on the assistant message as `proposal` with `type: "log"`, status `drafted`. The session proposal is `type: "session"`. A newer proposal in the thread makes an older one stale. The server sets the answers "Done" (`approve`) and "Add or change" (`change`).
- "Done" is plain code with no AI call, in one transaction, once. It writes one entry (the person's messages joined by a blank line, all files, `at` from the draft, label set from the draft, no `read_entry` job), then a session (`source: "import"`, `importId` = the entry id), a goal, a limit and a note when the draft holds them, each tagged with the entry id. `entry.read.made` lists the rows. The reply is a fixed text built from what was written ("Logged: ... Session added.") and carries `entryId`.
- Removing the entry marks the session it made as deleted. The goal, limit and note stay: no cheap check says whether the person edited them since.
- An entry that made a session is left out of the entries the coach reads, so the same words are not read as a note and as training.
- No AI answer: a fixed message, and Done saves a plain note of kind "other". Photos only and no image input: a fixed message, same Done. An invalid draft after the retry: a fixed message and no draft.
- Records never go to a provider (ADR-015); the log turn holds none (tested).

## Built in step D: goals, limits and notes in the same chat (2026-11-24)

The owner, 2026-11-24: "ok, continue and clean up everyting". Decisions below are Proposed: the owner has not confirmed them one by one.

- **The coach turn runs for every chat screen** except `program` and `start`: `chat`, `log`, `session`, `exercise` and the new `goal`, `limit`, `note`. A message with no screen keeps the old reply. (Proposed)
- **One draft mechanism.** `draft_log` and its stored `proposal` carry a goal, a limit or a note in any chat; nothing parallel was added. Outside the log chat the draft holds only those three parts, has `noEntry: true` and no category, and Done writes the parts and no log entry (the log chat keeps its entry). A draft of a meal or a workout outside the log chat is rejected with a reason; the coach tells the person to use Log. A session part outside the log chat is dropped. (Proposed)
- **One goal path: the coach turn fills the structure.** The goal part is under `GoalInputSchema`. Code keeps `exercise` only when it names an exercise of the log (the check the job `parse_goal` did). Done writes the finished goal. The job `parse_goal` and its test were deleted. Reason: approve then needs no AI call (ADR-032 write class), and one writer cannot disagree with another. With no AI the goal chat drafts the person's words with kind `custom` and the numbers a plain pattern finds. (Proposed)
- **Edit by draft.** `edits: { goalId?, limitId?, noteId? }` marks a part that changes an existing row; the part holds the whole new value. The turn input lists the person's goals, limits and notes with ids (limits as kind and text of rules only, no exercise lists, no records, ADR-015). A limit change keeps stored exercises of an unchanged rule, the records and the check-ins. (Proposed)
- **Deletes are never done by AI.** There is no delete function. The coach says where the person deletes; every delete in the app asks first.
- **Exact edits stay exact.** Done and delete of a goal, the status toggle, the rule sheet and the records of a limit, the switch and the remove cross of a note stay plain forms and taps.
- **App.** "Add goal" (and a tap on a goal), "+ Add" under Limits (and "Add a limit here" on the figure, with the body part; the limit detail has "Change with the coach"), and "+ Add" under Preferences (and a tap on a note) open the one chat with the context `goal`, `limit` or `note`, a context line and a hint in the composer. The draft card has the same frame as every draft: "New goal" or "Change goal", the parts, then "Done" and "Add or change". After Done the chat ends with "Saved" and Close. The free-text goal form, the add-limit sheet and the add-note sheet were deleted.
- **One composer widget.** The note on Start step 2, the Home import screen and the form that changes an existing log entry use the same composer widget as every chat. The widget can hide the parts a use cannot take: Start step 2 holds one text, so it shows the text field only and keeps its own Start button; an import has no text, so it shows no text field and the files wait in the strip until send; the entry form shows everything and send saves. (Proposed. The owner's rule is the same UI with text, photo, file and camera. The start request takes only a text and an import takes only files, so those two cannot use every part until the backend takes them.)
- **What the coach no longer does in the general chat.** The old reply job also ran `title_thread` and `extract_from_chat` (which wrote goals and notes at once, with no Done). The coach turn runs neither: a thread keeps the title code made from its first message, and a goal or note comes only through a draft the person approves.

## Proposed next steps (not built, not confirmed by the owner)

- The app sends every message through the one chat with its context; "Change plan" and the exercise comment open that chat.
- The app's Log button opens this chat (built in the app).
- The program and start screens move to the coach turn.
- `learn_place`, `chat_program` and the separate start rebuild fold into the coach turn; the old routes go.
- The trace of a turn also stores the result of each action.

## Consequences

- One balance-board message changes one exercise and the Gym text in one turn, and the session stays at the Gym (tested with a stubbed provider, `tests/coachTurn.test.ts`).
- A turn costs one AI call, two on a retry. It reads the same bounded context as a chat reply plus the screen data.
- A wrong action is limited: it can change only the unfinished part of the open session and a place text, and the place change is in `placeChanges` with the person's words.
- Not verified: how a real provider chooses the functions. The tests use the mock and a stubbed provider.
