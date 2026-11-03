# Show example code in the query pane

`idea` · 2026-11-03

## Problem

In the query modal (`<leader>q`), the left pane only shows code that already exists: the selection plus related code read from disk. When the answer would be clearer with code that doesn't exist yet, there is nowhere to show it.

## Idea

Let the left pane also show **example** code that does not exist in the project, but only when it is needed.

## Decided

Implemented 2026-11-03 (`lua/query.lua`, self-check `tests/query.lua`).

- **Needed:** two stages. Jev (one Noul, ~0.4s, before the answer) only says whether example code would help: the user asks for an example or to be shown how to do something. They learn with this modal and never ask to have code written, so examples are minimal and commented to teach. Jev sees the question and the selection, not the project. When it says yes, Sonnet gets permission and makes the call with the project in hand: real code via `@@related` if it exists, `@@example` only for what doesn't, or nothing. Jev failing means no examples, as before.
- **Told apart:** a `── ejemplo · <title> · no está en tu código` header and the whole block tinted with `DiffAdd`. `c` in the answer copies it.
- **Alongside:** right under the selection, above related code. When a long selection pushes it out of view, the pane scrolls to it. Unlike related code, it stays until a newer example replaces it, because follow-ups often ask about it and Jev rightly reads "explain the example" as no new code. Follow-ups also see earlier examples in the history.
- **Measured:** gate 70/71 on labeled questions, learning phrasing included ("enséñame…", "explícame cómo hacer…" vs "explícame cómo funciona…"), at 0.3–0.6 in two runs (cut 0.4, recall first). Every default question from `query_kinds` scores ≤0.21, so the common path never triggers. In end-to-end runs Sonnet skipped the example when real usages existed and wrote one when they didn't.
