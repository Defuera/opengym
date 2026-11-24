# Evaluation framework for the AI coach: design

Status: design, not built. Written on 2026-11-18 by the owner's assistant (Claude) together with Astra (`gpt-6-astra`), which reviewed the first draft. The owner's direction: "It's up to you to decide if my real sessions are good and if my conversations are good. Maybe you better generate proper test data."

## Purpose

1. Measure the coach with a fixed set of cases, so that a change is judged by a result and not by a complaint.
2. Move each AI job to the cheapest model that keeps the quality.
3. Let an agent improve prompts and inputs by itself against that measurement (the idea of Karpathy's autoresearch: change one thing, run, keep it only if the metric is better).

## What is measured

Four jobs: `build_session` (today's session, place, rebuild from feedback), `chat` (the coach turn on a plain chat, ADR-032; only its message is judged), `parse_log` (free text to session structure), `learn_place` (equipment note of a place).

The result of a run is not one number. It is four numbers per job, read in this order:

1. **Gate pass rate.** Checks by code that must hold. Release needs 100%.
2. **Task success rate.** Each case lists what a right answer must contain. Share of cases that meet their list.
3. **Quality win rate.** A judge model compares the new answer with the answer of the current version, case by case.
4. **Cost and time** per case, with the fallback rate and the retry rate.

A later number never makes up for an earlier one. A pleasant answer that breaks a limit has failed.

## Test data

No real personal data. The data is designed.

- **Eight personas:** beginner at home with two dumbbells; gym lifter with a knee limit and a ski goal with a date; person who returns after a break; runner who lifts once a week; traveller in a small hotel gym; older lifter with several limits; person who logs carelessly; experienced lifter in an easy week.
- **Logs made by code, not by an AI.** A small generator holds a state per persona (training days, missed weeks, progression, fatigue, easy weeks, places and their equipment, limits with start dates, goals) and writes 8 to 10 weeks of sessions from it. Checks then prove the log is consistent (no equipment the place lacks, no impossible jump in weight, an easy week is lighter).
- **Each place has an equipment list in two forms:** the free text the coach reads, and a fixed list the checks use. This makes "the plan uses only what is there" a check by code.
- **Cases** are (persona, day, request, note, feedback rounds) for sessions; a scripted user with fixed messages for chats; single texts for `parse_log`; short sequences of sentences for `learn_place`.
- **Trap cases**, taken from real complaints and from Astra's list: a note against a limit; a request for a forbidden movement; equipment missing at the place; a place with unknown equipment; "no water bottles" after a plan with bottles; feedback that contradicts earlier feedback; an easy week; no history; a very short session; a free request that means a known activity; an unclear log text; a log text in two languages; an exercise named without sets; dates said as "yesterday"; a chat where the user declines advice and then asks a question; a chat question about a muscle; a chat with a photo; a sentence about another place.
- **Size.** First set: about 30 cases, the known complaints. Full set: about 160 (48 sessions, 36 chats, 48 log texts, 32 place sequences), balanced over the personas. Two parts: one to tune on, one held back.

## Scoring

- **Gates (code).** Valid output after the real pipeline (`runJob`, then `finalizeStartProposal`, so we score what the user would see). No movement a limit forbids. Only equipment of the chosen place. The right place. The fixed activity name kept. Feedback respected. Size fits the minutes. `parse_log`: no invented number, right date, right measure. `learn_place`: an unrelated sentence changes nothing; only the named place changes. `chat`: no claim about data that is not there.
- **Task success (code where possible, judge where not).** Per case: "names the triceps", "does not repeat the advice from turn 1", "has at least four exercises", "uses the dumbbells".
- **Quality (judge).** The judge sees two answers to the same case in random order and picks the better one, with a short reason. No 1 to 5 marks: Astra's point, which we accept, is that such marks look exact and are not.
- **Is the judge right?** Without the owner's labels we use three controls:
  - Planted bad answers (a plan with a forbidden exercise, a chat answer that repeats itself). The judge must reject them. If it does not, the run is void.
  - About ten reference answers, written once by a strong model and reviewed by Claude and by Astra.
  - Two judges from different model families on a sample. Low agreement is reported, not hidden.

## Is a difference real?

The models do not answer the same way twice. So: three answers per case when tuning, five when confirming. A change counts only when no gate gets worse, the gain is at least 3 points, and it holds on a second run or on the held-back part. Smaller differences are called a tie.

## Cheaper models

Per job, run the same set on each candidate model. Take the cheapest model with no gate failure that is at most 2 points worse on task success and at most 3 points worse on quality than the best one. One job may stay on the strong model while another moves to a small one.

## The loop that improves by itself

- The agent may change one thing per try: the role text, the shape or order of the input, a few examples, the model, a provider setting.
- It may not change the cases, the checks, the judge or the thresholds. Those files are protected by a hash.
- A try is kept only by the rule above. The order of goals is fixed: gates, trap cases, task success, quality, cost, time.
- A budget per batch (for example 20 tries per job). Every try is stored with its prompt, outputs, scores and diff.
- Nothing ships without the owner. The agent ends with a proposal and the numbers on the held-back part.

## Where it lives

`backend/convex/evals/` with `generators/`, `fixtures/`, `assertions/`, `judges/`, `runner/`, `reports/`. It imports the real job code (`JobDef`s, `coachPicture`, `runJob`, `finalizeStartProposal`, the rules). It builds its input in memory. It never reads or writes the live database. A separate command runs it, so the normal tests never call a provider.

## Build order

1. About 30 cases for the known complaints, with gates, run on the real jobs. Useful at once.
2. Persona generators and their consistency checks.
3. The full set and a report per job.
4. The judge, planted bad answers, references, agreement.
5. Repeated answers, the "is it real" rule, the held-back part.
6. Model comparison with cost and time.
7. The loop.

## Where Claude and Astra differ

- Astra wants the full 160 cases with three answers each from the start. Claude starts with 30 and grows, to keep the first runs cheap and to learn which cases matter.
- Astra says repetition in a chat cannot be a check by code. Claude keeps a code check as a warning only and lets the task-success list decide.
- Chats: the scripted user's messages are fixed and do not react to the coach. This is repeatable but less real. A user played by a model is left for later.
