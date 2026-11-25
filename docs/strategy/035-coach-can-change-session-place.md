# ADR-035: The Coach Can Change the Place of the Session, and a Rebuild Keeps It

## Status

Accepted

Note: the owner asked for this on 2026-11-25. About a live trace he wrote: "Can you investigate why it got confused? Because it knows that the place is gym, but it asked me what I have at home." His standing rule for coach functions (2026-11-24): "start as free as possible and restrict agent on the need basis." On who may set the place: "Both me and the app and Claude should be able to update the location."

## Date

2026-11-25

## Context

The owner started a session of the activity "Gym". By plain code it got the place "Home", the place last used for that activity. The chat header chip showed "Gym, Legs · <exercise>", with no place. He asked for his usual upper-body session. The coach read `sessionPlace: Home` correctly, planned for home dumbbells and asked "Do you have a bench and cable setup at home?". He said by voice: "I'm not at home, I'm going to the gym." The coach answered that the session was still set to Home, that it could not change the place from chat, and that he should select Gym in the app.

Cause in code (read at `model/ai/jobs/coachTurn.ts` and `model/coachTools.ts`): the prompt said "No function changes it", and no function for the place existed. The rule came from ADR-032 ("The place of a session is a fact the person chose. No function changes it") and its tool list in ADR-021's line of work. The person had to leave the chat to fix a fact he had just told the coach.

A second trace, read from `aiCalls` on 2026-11-25: on 24 Nov the Start job `build_session` first chose the place "Gym". The person pressed regenerate with the feedback "I do have balance board". The second `build_session` call returned the place "Home" (the Home place text lists a balance board; the model guessed). The session was saved at Home. The next day "last used for this activity" was Home as well. The person never said he was at home. Cause in code: the rebuild input carried no place, so the model chose again.

## Decision

- **Three ways to set the place of a session.** The person, on the session screen (the place mark, exists). The app, by plain code (the default at Start: the place of the last session of the activity, or the place the coach names, ADR-021). The coach, from chat, with the new function `set_session_place`.
- **`set_session_place { placeId }`.** Only a `placeId` from `places` in `INPUT_JSON`, and only when a session is open. Applied at once and reported like the single-exercise functions; the action line reads "Place: Home → Gym". The server writes `openSession.placeId` with the other session changes of the turn (`rev + 1`, `updatedBy: "coach"`). The phone takes it as every outside change (ADR-028: `applyRemoteActive` copies the place). The new place counts for the rest of the turn.
- **When the coach may use it.** Only when the person's own words in this chat say where they are or will train ("I'm at the gym", "I'm going to the gym"). Never from the coach's own guess, and never because a place lacks an item (`SESSION_PLACE_RULE` stays). In the same reply the coach may go on with the request for the new place's equipment, for example `rebuild_open_session` planned for it. When the person names a place that is not in `places`, the coach asks. Creating a place from chat is not part of this decision.
- **The header chip shows the place.** The chat of an open session shows a location icon and the place name after the activity and focus ("Gym, Legs · Brisk Walk", then the place). With no place, nothing extra shows. It follows the session, so a change by the coach shows at once.
- **A rebuild keeps the place.** A start request with feedback keeps the place of the proposal the person saw (`startRequests.previousPlaceId`). The model gets it as `currentPlace`. The prompt says: the place stays; change it only when the feedback names a place or says where the person is; a mention of equipment is knowledge about the current place, not a statement about the place. Code guard (`pickPlace`): when the model returns another place and the feedback does not contain that place's name (case-insensitive, same key as `activityKey`), the previous place stays.

## Consequences

- This replaces one rule of ADR-032 ("No function changes it") for the open session. The text of ADR-032 and ADR-021 stays as it was; ADR-032 has a pointer to this record. The rule "never choose or imply a different place because a place does not name an item" stays.
- The guard compares by name text. Inference: a feedback that names the model's place for another reason ("no bench at home") lets the model's place pass; this was accepted as simple and rare, not measured.
- A place the person names that does not exist gets a question, not a new place. Creating places from chat can be a later step.
- Prompt wording was not run against a real provider. One eval case (`ch-set-place`) was added; it has not been run.
