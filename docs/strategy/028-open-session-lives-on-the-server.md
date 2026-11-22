# ADR-028: The Open Session Lives on the Server, With a Copy on the Phone

## Status

Accepted

Note: the owner decided this in the session of 2026-11-22. He asked the operator to change the session open on his phone, and the operator could not: that session was on the phone only. His words: "everything should be streamed from convex with local cache on case network is down I think". To the proposal below he said: "Go".

## Date

2026-11-22

## Context

Finished sessions, goals, limits and notes are stored on the server and streamed to the app, with a copy on the phone and an outbox for changes made offline. The open session was the one exception (verified by reading `apps/mobile/lib/store.dart` and `apps/mobile/lib/data/shared_prefs_session_repository.dart` on 2026-11-22): it was saved only on the phone until the person finished it.

So nothing outside the phone could change it. A plan of the coach that came late could not arrive by itself. The server could not see what was planned against what was done. A lost phone lost the session in progress.

## Decision

- The open session is one row in the table `openSession`, in the app's own shape. There is at most one.
- Logging stays local first (ADR-003). Each change is saved on the phone at once. The app sends it to the server after, and marks on disk that a change is not sent yet. Offline, the mark stays and the change goes out when the connection is back.
- The app subscribes to the row. It takes the server's copy only when the phone holds no unsent change and the server's revision is newer than the one the phone has. That is a change made outside the phone.
- When the phone and an outside writer change the session at the same time, the phone wins. The person's hands are on it.
- A set marked done is a fact, and only the app writes facts (ADR-002). An outside writer goes through `jobs/openSession:replacePlan`: plain code keeps every exercise that has a done set exactly as it is and replaces only the rest.
- The row is not a fact. The session becomes a fact when the app finishes it and sends `commands/sessions:save`, as before. The app then removes the row.
- A session that ended on the phone is never opened again from the server: the phone keeps the id of the ended session until the server has dropped the row.

## Consequences

- The coach, the owner's tool or a second device can change the part of the open session that is not done, and the change appears on the screen.
- A session in progress survives a lost or new phone.
- The server holds planned against done while the session runs. The quality measure can use it later.
- An outside change that arrives while the phone holds an unsent change is lost. This is the price of "the phone wins".
- A running countdown is cancelled when an outside change replaces the plan.
- Not done here: the coach does not write to the open session yet (a late plan is still offered on the session screen), and the screen does not say that a change came from outside.
