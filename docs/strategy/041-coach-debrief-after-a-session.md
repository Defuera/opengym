# ADR-041: The Coach Debrief After a Session: an Evaluation That Ends With a Question

## Status

Accepted

Note: the owner asked for the change in the session of 2026-11-26 (words below). The design details (the facts block, the thresholds, the thread id, the prompt) are the builder's and are not confirmed by the owner. Where this text says "inferred", no source or live check backs it.

## Date

2026-11-26

## Context

After a finished session the app showed a "Coach review": two sentences and up to five lines, one per exercise (`review_session`). The review got no plan, and the prompt told the model to say what moved against last time, with the numbers. The recap screen then listed the same sets below it.

The owner's words (2026-11-26):

- "I'm reading summary and I don't like it. It's boring and it's kind of useless for me."
- "I know what I did during the session. What's the point of repeating it? I need an evaluation, not the summary of what I did. I know what I did, and below, immediately, I see again what I did. What's the point of AI to reiterating to me what I did? That is completely pointless."
- "I want it to be more human. It's like, imagine I would train this coach, and he was like, okay, dude, ... I see that you pushed harder. That's pretty good. I think we can keep it up. Are you sure you didn't feel any pain? How do you feel right now? Maybe we should also like open a chat and have AI ability to ask questions ... it would make sense for me more like, oh wow, dude, that's a big jump. It's pretty good, but are you sure that you feel okay? Or it's like, all right, looks like we're progressing faster than expected. Good job. I think you can be ready for your ski session"
- "what I did bad, what I did good, what I should be looking for next session, maybe some encouragement or maybe some kind of pushing, it's like, oh, you were lazy today or something like that."
- About the recap screen: "Session summary skill screen. Let's put everything upside down. First, let's have a figure go with muscles, then the summary, and then the then the log, because log is less important. I just did it, so I know what I did. Doesn't make sense to put it first. And also, maybe even let's put the AI summary first and then the figurine."

## Decision

The review becomes a debrief: an evaluation in the coach's own voice that ends with one question. The answer opens a chat about that session.

### 1. The plan stays with the finished session

A session may keep the plan it started from (all fields optional; an old session or one without a plan has none):

- `planNote` on the session: the coach's reason for the plan.
- Per exercise `planned`: the sets as the plan had them when the exercise entered the session (reps, kg, max; or minutes, distance). `planNote`: the coach's note of that exercise.
- `skipped`: planned exercises that were removed, or left with no done set (name, measure, planned sets).

Done sets are stored as before. Where the plan is captured: the app copies the plan sets into `planned` when the plan becomes session exercises (`PlanStore.exercisesOf`); the server does the same when the coach adds or replaces an exercise (`toOpenExercise`). The person edits `sets`, never `planned`. `AppStore.finish` and `AppStore.discardExercise` build `skipped`.

### 2. Facts are made by code

`model/reviewFacts.ts` (pure, unit-tested) makes the `facts` of the review input from the whole history of the user:

- per exercise: the best set today; the last earlier session with the same exercise (the same name after trim, case and space folding, no fuzzy match) with its date and best set; the signed change as text ("+5 kg", "+2 reps at the same weight", "same"); `firstTime`; `daysSinceLast`;
- against the plan: per exercise planned and done (sets and top set) with a verdict (more, less, as planned; compared by reps times kg, or minutes); skipped planned exercises; added exercises that were not planned;
- session level: duration, done sets, and the usual of the same activity and focus over 8 weeks (median minutes and sets, and "more / fewer or shorter / about the same" within 20 percent), only with at least 3 such sessions;
- program position when a live program runs on that day: week x of y, sessions done and planned this week, days to the end of the program;
- the person's comments, the session note and the body log entries of that day, word for word.

The prompt says these are the only numbers the model may use. A code check refuses a message with a number that is not in the data, and the model retries once (inferred: this keeps the model from doing arithmetic; not measured).

Not built: "days to the goal date". A goal has no date field; a date written in the goal title ("Ski on 19 December") reaches the model as text only.

### 3. The new review

`review_session` returns `{ message, question? }` instead of `{ summary, changes }`.

- `message`: 2 to 4 short sentences in a natural voice. It evaluates (good, not good, where the person stands against plan, program and goal, one thing to look for next time). It does not read the log back. Praise needs a reason in the facts; a push needs a sign in the facts.
- `question`: one question about what the coach cannot see (pain, how a limited body part took the load, effort, how the person feels, why something was skipped), with 2 to 4 short answers. The answer ids are made in code.
- Fallback: no review. The job stores nothing when the AI gave no valid answer. The old plain-code review (a count of the log) is removed: it was the thing the owner called pointless. Old stored reviews (`summary`, `changes`) are still read and shown.

### 4. The recap order and the chat

The recap screen shows, from the top: the header (date, duration, place), the debrief, the body figure, the log. While the debrief is being written a quiet line holds its place. With no review the slot is empty.

The debrief shows as a coach bubble with the question and its answers. `commands/debrief:open` makes the one chat thread of that session (the thread id comes from the session id, so a second tap finds the first thread). The first message of the thread is the debrief (`message` and `question`). A tap on an answer sends its label as the person's first message; a typed or spoken reply goes through the normal chat composer. The normal `coach_turn` replies, with its normal functions (draft a body log, a limit note, propose a program change). Reopening the recap shows "Continue in chat" once the person answered.

The next plan and the next chat read the newest debrief exchanges of the last 14 days (the question, the answer, the date) as `afterSession`, in the picture of `build_session` and in the input of `coach_turn`.

## Evidence

These findings are from a web search on 2026-11-26, not verified by us:

- A meta-analysis of coach autonomy support (131 samples, N = 38,844) links it most strongly to self-determined motivation.
- Self-efficacy is associated with exercise adherence.
- One small app study (89 active participants) found emotional messages more effective than logical ones.
- A 2020 systematic review found coach and athlete ratings of exertion agree only moderately, so the coach has to ask.
- No study tests the format of a post-session summary.

The design above is our inference from these findings and from the owner's words, not a result of them.

## Consequences

- A session finished with the AI off or failing has no review. The recap shows no debrief.
- The review costs about the same as before (a smaller prompt; no log to read back). Not measured.
- Opening the debrief chat needs a connection. Offline, the app says so and nothing is lost.
- The model may still write a number that is in the data but wrong for the sentence. The check only tests that the number exists in the data.

## Not decided

- Whether the debrief question may be skipped on days with nothing to ask (the prompt allows it; the owner expects a question most days).
- How long a debrief answer counts for the next plan (14 days now).
