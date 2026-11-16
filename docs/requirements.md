# Requirements

How to read this file: each line has a code (R01 to R52, A01 to A16) and the owner's plain wording. Use the wording. The code is only a reference.


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
- R11 Everything is logged; no activity type is second-class

## Home
- R12 Opens on "how am I doing?"
- R13 Shows stats
- R14 Shows goal progression
- R15 Shows last week / last month progress

## Starting a session
- R16 Plus button starts an activity
- R17 App predicts what you're about to do
- R18 Predictions ordered most-likely first
- R19 Gym → a session is generated to follow
- R20 Exercises can be reordered
- R21 Exercises can be swapped
- R22 Session is prepared, edited only as needed — never a blank slate

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

## Open questions (the owner's list, still undecided unless noted)
- Which activities are in v1 besides gym
- What context inputs exist beyond injuries
- Whether health-app import is v1
- Backend choice and schema — a first answer now exists (see [ADR-006](strategy/006-standalone-backend.md)),
  not yet confirmed by him
- Programmes per activity or combined

See also: [strategy/README.md](strategy/README.md) for the decisions taken so far, and [design.md](design.md) for the visual design.
