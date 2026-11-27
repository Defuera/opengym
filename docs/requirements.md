# Requirements

**These requirements are frozen (owner's rule, 2026-11-23).** The owner said: "I think we should keep a list of requirements that I made frozen and not change them unless I explicitly ask for it." So:

- Do not change, drop or work against a line of this file unless the owner asks for that change in his own words. Quote his words and the date beside the change.
- A proposal from an agent or a model (a design review, a simplification, a second opinion) is not such a request. Check it against this file first, and name the line it would change before you show it to the owner.
- A new feature must fit the lines that already stand.

How to read this file: each line has a code (R01 to R52, A01 to A16) or a date and the owner's plain wording. Use the wording. The code is only a reference.


Source: the owner's flat list (R01–R52) plus what he added later in the same
conversation (A01–A16). Wording is kept close to his.

## Purpose
- R01 Activity tracking app, first and foremost
- R02 Track multiple different activities in one place
- R03 Combine tracked activities into one programme
- R04 Build the programme from logged data

## Programme inputs
- R05 Goals are the first input
- R06 Circumstances/context are the second input
- R07 An injury is one context input, not the product
- R08 A goal may be releasing pain, fixing or working through an injury

## Logging
- R09 Logging gym activity must be convenient and pleasant
- R10 No extended typing or form-filling in the gym
- R11 Everything is logged; no activity type is second-class (Gym is one activity; Upper and Legs are focus labels inside it, not activity types)

## Home
- R12 Opens on "how am I doing?"
- R13 Shows stats
- R14 Shows goal progression
- R15 Shows last week / last month progress

## Starting a session
- Decided 2026-11-17, in plain words: gym upper and gym legs are not separate activities. The activity is Gym. The AI advises which exercises (the focus, for example Upper or Legs). The same holds for running: you just go for a run, and the AI may advise the session type. See ADR-013.
- R16 Plus button starts an activity
- R17 The Start tab lists the activity types of the log (both sessions with sets and time/distance), most used recently first. No AI ranks them (updated 2026-11-18)
- Confirmed 2026-11-23, the owner's words: "I want to be able to start: gym session, running session, wingfoiling session, home workout session. And this should be a dynamic list, that is filled as I start 'Other activity' that is not on the list." The list of activities on the Start tab stays. It is not replaced by one free-text field.
- R18 The most likely type is first and highlighted; a row shows only the type name
- R19 A type with sets → the user may add a note, then the coach decides the focus and builds the session to follow. The user does not choose the focus, and the session screen has no focus chips (updated 2026-11-18)
- R20 Exercises can be reordered
- R21 Exercises can be swapped
- R22 Session is prepared, edited only as needed — never a blank slate

## Start session and Log (ADR-016)
- Decided 2026-11-17: Home has two actions, **Start session** and **Log**. Each opens a bottom sheet. Nothing in the app is a fixed list: activities, foci and starter plans come from the log.
- A session with sets (`kind: "gym"`) may have any activity name in `type` (1..40, default "Gym"): "Gym", "Home", ... `kind: "activity"` is time and distance. Old rows stay valid. Names match by `activityKey` (lower case, trimmed, spaces collapsed); display uses the most recent spelling.
- Updated 2026-11-18 (two steps): "I choose the activity, the coach decides the content." Step 1 of the Start session tab lists the activity types of the log, most used recently first, one row per type with the name only (no focus, no reason, no coach pick). The first row is highlighted. Both kinds are listed. The last row is "Other": a name (1..40) and "Sets and reps" or "Time or distance". With an empty log only "Other" shows, with a short line. "Start empty, without a plan" stays. Step 2 (a type with sets): the type as title, one optional note ("Anything for today?", max 200) and "Start". The request carries the type as `name` and the note as `text`; the coach decides focus and plan, and the note wins. Offline or on failure the plan of plain code for that activity opens, else an empty session. A time/distance type opens the Log form for that activity. The open session shows the activity, the focus and the coach's rationale as text; the focus cannot be changed there. The earlier Today card, the "today" request mode, the AI ranking of predictions and the focus chips were removed.
- With an empty log there are no proposals and no starter plan: the fallback is an empty session. Plans are stored per activity and focus, only for the first 3 set-based proposals; any other is built from the user's own last session of it, or empty. Safety limits and the avoid rules still apply.
- Log lists time and distance activities from the log and opens the small log form. No AI call.
- Updated 2026-11-23, the owner's words: "There must be no specific routes for such things. What we need is a general log entry and then AI decides what this is." and "Let's just have like a chat-like input field. So I can input text, image, or file. And then AI will decide how to log it... AI should return a message to me like ... log created. And then I can either accept it and complete, or I can keep chatting and add more information on the log." Log opens the coach chat. Nothing is written to the log until the person presses Done. This replaces the line "Log lists time and distance activities from the log and opens the small log form. No AI call."

## Inside an exercise
- R23 Follow the exercise set by set
- R24 Sets pre-filled from your own pattern (bench: 6×20, 6×40, 6×60, then max attempts)
- R25 ± controls for reps and weight per set
- R26 Complete action logs it
- R27 One or two clicks beyond adjustment

## Session screen
- R28 Current exercise = big card, centre
- R29 Exercise list above it
- R30 Reorder, discard, add from that list
- R31 Every action one or two clicks

## Chat
- R32 Chat mode for advice
- R33 Accepts statements, not just questions
- R34 Record audio into chat
- Confirmed 2026-11-25, the owner's words: "Now, when I'm recording voice, can we show a wave function, same as in Claude Code, so I understand that app can hear me? And also, let's place a text before sending transcription, so I can check that it is correct transcription." A live wave shows while recording, so he sees the app hears him. The transcript lands in the text field to be checked before sending.
- R35 Drop files (e.g. MRI)
- R36 Everything compiles into context

## Threads & memory
- R37 Multiple threads
- R38 One topic per thread (ankle, knee)
- R39 Threads separate for the user
- R40 One database at the core
- R41 AI searches contextually across all threads

## UI direction
- R42 Cube-build style: large buttons, super simple, visible
- R43 Looks like a modern mobile app, not a deck
- R44 Oversized thumb-reachable actions, one job per screen
- R45 Designed at 1080×1920 portrait

## Platform
- R46 Flutter
- R47 Backend and schema designed, not an afterthought
- R48 UI coherent with architecture
- R49 Architecture shown: Flutter client, one backend, one core DB, threads as views, retrieval across all

## Constraints
- R50 Nothing medical — no rehab framing, no doctor report, no clinical language
- R51 No invented metrics or testimonials
- R52 Open questions shown open, not filled with assumptions

## Added during the conversation
- A01 Session and exercise are ONE screen: exercise carousel on top, the
  selected exercise's sets and ± controls in a card in the middle. No Start
  button, no separate exercise screen. (Supersedes the separate screen implied
  by R23–R29.)
- A02 Home dashboard generated dynamically from the user's goals.
- A03 Hard-coded UI for gym input; AI-driven processing behind it; very strict
  data schema; an "AI engine" behind the UI.
- A04 Go to Flutter directly (no PWA phase); final-ish design, not grey-box.
- A05 Solid architectural foundation, SOLID principles.
- A06 Storybook-style tooling so designs are easy to rework.
- A07 Widgets completely standalone.
- A08 Use version control.
- A09 Functional end to end: set it up, put in API keys, test it. Not a shell.
- A10 AI providers interchangeable: Anthropic, DeepSeek, OpenAI.
- A11 Import: drop a bunch of files; AI maps them to the schema and stores
  them. One generic import for text files AND image files (no ChatGPT-specific
  importer). Example: a photo or screenshot of the cycling machine screen.
  (He has a lot of history in ChatGPT conversations he wants to bring in.)
- A12 A defined list of AI functions (what the AI in the app can do), e.g.
  generate home stats, generate a workout session.
- A13 Be mindful of token cost: sub-agents write code, the lead plans and checks.
- A14 He installs on his iPhone himself; he only needs the code.

## About me: limits, records, check-ins
- The owner can list body parts he trains around. Each is a limit with a status: active, improving or cleared.
- A limit has rules in training words: avoid, light or do. An avoid rule may name exercises.
- A plan that holds an exercise from an avoid rule is rejected. The code fallback drops it too.
- The AI gets the rules of non-cleared limits and the owner's records of every limit, cleared ones too. Owner's words, 2026-11-24: "What is the point of records of ai cannot read them?" (ADR-033).
- The owner can store his own records for a limit, word for word. The app keeps the text word for word and never edits or rewrites it; the AI reads it when he asks, and no AI function writes or changes a record.
- After a session that loaded a limited part, the app asks how it felt: fine, noticed or bad.
- The screen shows a load level per muscle for 14 and 90 days, and the muscles his goals name.
- See ADR-015. Backend contract: `backend/convex/functions/commands/limits.ts` and `queries/aboutMe.ts`.

## Coach model

- Settings has a "Coach model" section. The owner picks the model the coach uses, without a deploy.
- It shows the model in use, the provider, and (when he chose one) the default from the server.
- He picks from a list the provider offers, reloads the list with "Refresh list" (the list shows when it was updated), or types another model id.
- The choice applies to plans, advice, reviews and chat from the next request. If the provider refuses the model, the app falls back to plain rules.
- It needs a connection. Offline, the controls are off.

## One chat with functions (ADR-032)
- Confirmed 2026-11-24, the owner's words: "chat must be always the same interface. Always text, image, and photo. It should use the same UI always."
- Confirmed 2026-11-24, the owner's words: "it should be the same chat everywhere, and chat is just with functions, and AI knows which functions to call."
- Confirmed 2026-11-24, the owner's words: "When I open a chat, AI should know what is my current context and what I might want, but then I can report anything, and it can report anything in the app, and then the chat is the same. Super simple."
- Confirmed 2026-11-24, the owner's words about a place description: "I didn't describe my gym at all. So AI should have known where information is coming from, and this is not a full information." A place description is partial. Equipment that is not named is unknown, not missing. The coach may ask.
- Confirmed 2026-11-24: a comment on one exercise changes that exercise only. The owner's words: "I didn't need to completely change the session. I only needed to fix that one thing."
- Confirmed 2026-11-24, the owner's words: "I can say, I want to change the whole workout. And then the AI replies with the question, okay, that's what I understood... That's what I propose now. Do you approve or not? And if I approve, it will regenerate the whole workout." A change of the whole session is a proposal; it is applied when the person approves.
- Confirmed 2026-11-24, the owner's words: "let's have a dynamic categorization of logs, and maybe have them have like either a different color or different color border, something like that, so they're visually distinguishable."
- Confirmed 2026-11-24, the owner's words: "I think we probably should start as free as possible and restrict agent on the need basis". The coach has no per-screen limits on what it may do.
- Confirmed 2026-11-25, the owner's words (with a screenshot of the chat composer greyed out, "Offline. Chat needs a connection to send."): "Open chat, it's loading for some time, so I cannot input my message. It should not work like this. I should always be able to input my message and send, and then you can show loading or like sending if it takes time to send, and it can kind of fail also." The chat composer is never off. A sent message shows at once as "Sending…"; if it does not go out it shows "Not sent" with "Try again" and keeps its text and files (ADR-037).
- Confirmed 2026-11-26, the owner's words (with a screenshot of the chat composer holding one photo, with no mic): "be able to still record the voice when I add an attachment. And also I want to be able to add multiple attachments. And also when I'm choosing photo, I don't need to choose camera anymore because camera is already here." With attachments and an empty field the mic stays beside send; the photo library picks several photos at once; the "+" sheet has no camera row where the composer has its own camera button.

## Health store: Health Connect and Apple Health (ADR-036)
- Confirmed 2026-11-25, the owner's words: "I want two way information exchange" (about the phone's health store: Health Connect on Android, Apple Health on iPhone). Tracker data comes in for the coach; finished sessions go out.

## AI usage and more than one user (ADR-038)
- Confirmed 2026-11-26, the owner's words: "Yeah, I know that I'm the only one user today, but let's rework schema and database such that we're ready for multi-user. We will implement a login soon, and let's count tokens so we can evaluate approximately how much it will cost us to run this app and for how much should we sell subscription." Every paid AI call is counted with its tokens and a user id. The data model is being made ready for more than one user; the tables are reworked in a later step.

## The debrief after a session (ADR-041)
- Confirmed 2026-11-26, the owner's words about the coach review: "I'm reading summary and I don't like it. It's boring and it's kind of useless for me."
- Confirmed 2026-11-26, the owner's words: "I know what I did during the session. What's the point of repeating it? I need an evaluation, not the summary of what I did. I know what I did, and below, immediately, I see again what I did. What's the point of AI to reiterating to me what I did? That is completely pointless."
- Confirmed 2026-11-26, the owner's words: "I want it to be more human. It's like, imagine I would train this coach, and he was like, okay, dude, ... I see that you pushed harder. That's pretty good. I think we can keep it up. Are you sure you didn't feel any pain? How do you feel right now? Maybe we should also like open a chat and have AI ability to ask questions ... it would make sense for me more like, oh wow, dude, that's a big jump. It's pretty good, but are you sure that you feel okay? Or it's like, all right, looks like we're progressing faster than expected. Good job. I think you can be ready for your ski session"
- Confirmed 2026-11-26, the owner's words: "what I did bad, what I did good, what I should be looking for next session, maybe some encouragement or maybe some kind of pushing, it's like, oh, you were lazy today or something like that."
- Confirmed 2026-11-26, the owner's words about the session recap screen: "Session summary skill screen. Let's put everything upside down. First, let's have a figure go with muscles, then the summary, and then the then the log, because log is less important. I just did it, so I know what I did. Doesn't make sense to put it first. And also, maybe even let's put the AI summary first and then the figurine." The recap shows the coach's debrief first, then the figure with the muscles the session loaded, then the log of sets.
- The review after a session is an evaluation in the coach's own voice. It never restates the log. It ends with a question, and the answer opens a chat with the coach.

## The AI coach
Requirements for how the coach thinks and behaves. The owner asked for this section on 2026-11-27: "let's add a specific subsection of requirements for AI assistant."

- Confirmed 2026-11-27, the owner's words: "one of the requirements should be to have the sessions be adaptive, like to look into previous history and adhere to the kind of time and maybe location." And the same day: "by this point I should know that I go in the morning on weekdays, like for like an hour ... it's not getting adapted to my routine." Shortened by the owner the same day: "Be shorter, like: Sessions should be adaptive taking into account users habits, average session time and..." Sessions are adaptive: they take into account the user's habits, usual session time and place.
- Confirmed 2026-11-27, the owner's words about a computed time budget with its own prompt rule: "This is too specific. Code just needs to get information on my work hours. That's it ... You're trying to be kind of too detailed and too nudgy. It's not how it should work. AI can solve this." The coach gets the information and reasons from it. A special rule for one case is not the way (ADR-042).

## Open questions (the owner's list, still undecided unless noted)
- Which activities are in v1 besides gym
- What context inputs exist beyond injuries
- Whether health-app import is v1
- Backend choice and schema — a first answer now exists (see [ADR-006](strategy/006-standalone-backend.md)),
  not yet confirmed by him
- Programmes per activity or combined

See also: [strategy/README.md](strategy/README.md) for the decisions taken so far, and [design.md](design.md) for the visual design.
