# Show example code in the query pane

`idea` · 2026-11-03

## Problem

In the query modal (`<leader>q`), the left pane only shows code that already exists: the selection plus related code read from disk. When the answer would be clearer with code that doesn't exist yet, there is nowhere to show it.

## Idea

Let the left pane also show **example** code that does not exist in the project, but only when it is needed.

## Open questions

- What makes example code "needed": the question itself, the model's judgment, or an explicit request?
- How is example code told apart from real code in the pane, so it is never taken for code read from disk?
- Does example code replace the related code for that turn or appear alongside it?
