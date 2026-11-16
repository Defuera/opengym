# Design

There is no Figma file. The design was made on a Claude design canvas:
https://claude.ai/artifact/NXA77YKhBzvoNYptwzxFeh

The canvas is private to the owner. Open it in Claude to view or edit it.

## Artboards

All artboards are 1080x1920, portrait.

- Main (Home)
- Start
- Session (exercise carousel and sets on one screen)
- Chat
- Threads
- Architecture
- Open questions

The canvas source is one `.dc.html` file per artboard plus `canvas.json` for the layout. The files are HTML with inline styles. They read as a spec (sizes, colours, copy). They render only inside the canvas editor. The source files are not in this repo.

## Prototype

The tested web prototype is at https://claude.ai/artifact/79oMLGHZEkaBcuHziMMs2i. Its code is `apps/prototype/index.html`. It is the behaviour reference for the Flutter app.

## Gaps

The canvas is older than the end-to-end build. These screens have no artboard: goals, import, settings and the dynamic home modules. They follow the same visual tokens. See `apps/mobile/lib/theme.dart`.

## Visual tokens

Source: the handover notes (DECISIONS.md, section "Product and UI").

| Token | Value |
|-------|-------|
| Ground | `#F2F1EC` |
| Ink | `#121212` |
| Card | `#FFFFFF` |
| Muted | `#5C5A55` |
| Soft | `#E4E2DA` |
| Accent | `#2448E8` |
| Done | `#DCE3FF` |
| Border | 2 px, ink colour |
| Corner radius | 16 |
| Shadow | hard offset (0, 4), no blur |
| Touch targets | big |
| Theme | single, light |

## Interaction defaults

- Weight step is 2.5 kg. Reps step is 1. (Assumed, not confirmed by the owner.)
- Activities logged by time use a 5 minute step.
- Reordering moves an exercise one place earlier per tap. Long-press drag would suit a phone better. It is not built.

## UI direction (from the requirements)

- Large buttons, very simple, clearly visible.
- Looks like a modern mobile app, not a slide deck.
- Oversized thumb-reachable actions. One job per screen.
- Session and exercise share one screen. No Start button.

See [requirements.md](requirements.md) and [strategy/README.md](strategy/README.md).
