# One query modal: Jev routes answer, change or mix

`idea` · 2026-11-06

## Problem

The query modal (`<leader>q`) answers, and since `cs -e` it also edits the current file through a diff to approve. With two keys (`a` answer, `e` edit) the user picks the mode before typing, and the wrong pick is common: «¿Puedes hacer una función más compleja?» sent as a question got «no puedo editar, usa `cs -p`».

## Purpose (what the modal is for)

A companion scoped to the selection or file, learning first: understand code and learn how to write it. Next to that, an inline editor for this file only, where nothing changes without approval (`y`, or a typed approval) and other files are listed, never touched.

## Decided

Implemented 2026-11-06 (`lua/query.lua`, `lua/edit.lua`, `cs -e`; self-checks `tests/query.lua`, live eval `tests/query_route_eval.lua`).

- **Routes, by what the user gets back:**

  | Intent | Gets | Route |
  |---|---|---|
  | Understand (what, why, where) | text + real related code | answer |
  | Learn how (teach me, an example) | text + example to copy, never applied | answer + example gate |
  | Review / diagnose (is it right, why it fails, how to improve) | text + a fix offered, if one is warranted | mix |
  | Change (do it) | summary + diff | edit |
  | Reply to the change on screen (ok / cancel) | applied or dropped, no model call | settle |
  | Unsure between understand and change | text + a change offered | mix |

  Learn and change connect without merging: «aplícalo» after an example goes to edit with the example in the history.
- **Jev, one request (~0.4s), all questions in parallel, same state** (`question`, `previous_question`, `previous_turn`, `code`, `file`): the example gate; `route_edit` and its inverse `route_answer` (Nouls, averaged: steadier than either alone); `route_kind` (Choice understand / learn / review: a Choice separates review from learn, a "would a fix help" Noul fired on learning questions too); and `pending` (Choice approve / reject / other), read only when the previous turn left a change waiting.
- **Policy in code** (`M.route`): edit if p ≥ 0.6; mix if p ≥ 0.45 or review ≥ 0.7; else answer. Settle needs ≥ 0.8, because approving applies and saves. Jev failing means answer, as before routing.
- **Mix** runs `cs -q` (told a diff comes, so it explains without writing the change or saying it can't edit) and `cs -e` (told the change is an offer: empty edits if none is warranted) in parallel. The diff owns the left pane. A mix with no change says «sin cambio que proponer».
- **UI:** `a` opens the box on Auto; `e` on Editar; Tab in the box forces a route for one send (Auto → Solo consulta → Consulta + cambio → Editar), and Enter on an empty box re-sends the last request that way, which is the quick fix for a wrong route. Auto-routed turns name Jev's pick in their header. An answer while a change waits keeps the diff, so asking about a proposal doesn't lose it.
- **Measured** (135 labeled cases incl. every `query_kinds` default, 4 rounds): 98.9 % acceptable routes. No request for a change was answered with only text, and no question was turned into an edit; the one costly miss is «de una» as an approval (0.71 < 0.8, so it re-proposes the change instead of applying it). Every other approve and reject was right. The example gate stays at 152/152 with the new state field. Thresholds and wording were chosen against alternatives in the same runs (single Noul, short wording, Choice change/answer, Choice with three intents). Re-run `ROUNDS=4 nvim -l nvim/tests/query_route_eval.lua` after touching any question.
- **Known limits:** criteria carry the user's dialect for approval («dale»), so that case is not held out. Jev varies about ±0.1 between calls; cases near a cut can flip.
