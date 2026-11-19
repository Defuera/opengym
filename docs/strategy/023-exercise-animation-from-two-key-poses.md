# ADR-023: Exercise Animation From Two Key Poses, Redrawn From Open Photos

## Status

Accepted for the feature; the details below are Proposed.

Note: the owner asked for the feature in the session of 2026-11-19 ("create animation for every exercise ... for every exercise, we will need to do one API call ... store it in animation on the server", then "just implement the feature end to end"). He proposed 16 frames in one image and asked whether a source is needed. The two-pose form, the source and the style are the agent's choices from the tests below; he has not confirmed them yet.

## Date

2026-11-19

## Context

The session screen names an exercise but does not show the movement.

Tests on 2026-11-19 (outputs in the task workspace, `shots/anim/`):

- One image call that asked for 16 frames of a squat in a 4 by 4 grid returned 8 frames; 6 of them showed nearly the same pose, and one had an invented object. Verified by looking at the image.
- One call to OpenAI `images/edits` (`gpt-image-2`, 1536x1024, quality medium) with the two photos of the leg press from free-exercise-db returned both poses, correct, in the app's style. The same worked for the lat pulldown. A call with no photos (wall sit) also gave two correct poses. Verified by looking at the three images. Three exercises are not proof for every exercise.

The data set free-exercise-db (github.com/yuhonas/free-exercise-db) is released under the Unlicense. 873 of its 876 exercises have two photos: start and end. Read from its `dist/exercises.json` and the GitHub licence field on 2026-11-19.

## Decision

- An exercise animation is ONE stored image with two panels: left = start position, right = end position. The app shows the halves in turn. The server does not cut the image.
- One image call per exercise name, once. The result is stored in file storage and found by the normalised exercise name (table `exerciseArt`).
- Source of the poses: the two photos of the matching free-exercise-db entry. An AI job (`match_exercise`, the normal pipeline of ADR-004) picks the entry from a shortlist made by code, or says none. With no match the image is drawn from the name alone.
- A compact index of the data set (id, name, equipment, muscles) is in the repo, pinned to a commit of the data set. The photos are fetched from that commit when an image is made.
- Style: flat outline figure, white body, working muscles in the app's blue, equipment light grey, the app's ground colour. The style is text in the prompt (`artPrompt`).
- Art is requested when a proposal is saved and when the app shows a session. At most 40 new images in 24 hours.
- Only the exercise name and the public photos go to the provider. No log data, no record (ADR-015).
- The image is derived content, not a fact about the user (ADR-002 is not touched).

## Consequences

- An image can show a wrong or odd movement. Nobody checks an image before it is shown. Open: a check step, or a way for the user to reject an image and get a new one.
- The two panels are not pixel-aligned, so the change between the poses can jump a little.
- Making an image needs GitHub (photos) and the image model at that moment. A failure stores `failed`; a retry is allowed after 24 hours.
- Only the OpenAI provider makes images. With another provider the art stays `failed`.
- The app loads images from the network; with no connection the session screen shows no animation.
