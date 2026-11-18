# ADR-021: Places and Their Equipment Are Learned by the Coach

## Status

Accepted

Note: the owner agreed in the session of 2026-11-18. His words: "I don't want to bother user with this too much. It should be a background thing handled by the AI", and "it would be nice to add a lil place icon and display it on session, so then if user wants to provide more data about the place they can. And it just goes via chat".

## Date

2026-11-18

## Context

The coach proposed a home session with water bottles as weights. The user has no such bottles; he has dumbbells. The coach gets one free note about the gym equipment (from an import) and nothing about home. The coach also does not know where the user trains today.

ADR-002 says the AI never writes facts by itself. ADR-018 made one exception (the structure of a session from the user's own text).

## Decision

- A **place** is a new fact: `{placeId, name, text}`. `text` is free text that says what equipment is there. There is no catalogue of machines and no form.
- A session stores the place it happened at (`placeId`, optional).
- The user never has to pick a place or type equipment. The coach picks today's place when it builds a session, from the activity, the note for today and the places it knows. With no hint, code takes the place of the last session of that activity.
- **Second exception to ADR-002:** a background AI job may change the `text` of a place, and may create a place, from the user's own words (feedback on a plan, the note for today, a chat message about the place). It asks nothing. The exception covers places only. Sessions, goals and limits stay under ADR-002.
- Each change is logged with the user's sentence it came from, so a wrong line can be traced and undone.
- The coach gets the short list of places with their equipment text, because it picks today's place in the same step. It plans with the equipment of the place it picked.
- The app shows a small place mark (icon and name) on a proposed session, a running session and the recap. A tap opens a small sheet: the other places (to correct a wrong guess) and a way to tell the coach more. Telling more is a chat about that place; the same background job reads the user's messages there.

## Consequences

- A wrong note gives a plan with the wrong equipment. The user's feedback on that plan corrects the note.
- The place text is one more input to the AI provider. It holds equipment only.
- The old imported note with the topic "equipment" moves into the place "Gym".
- A session logged by text gets the last place of its activity; the parse job does not guess a place yet.
