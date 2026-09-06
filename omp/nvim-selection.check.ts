// Self-check: bun omp/nvim-selection.check.ts
import { banner, contextMessage } from "./nvim-selection"
import assert from "assert"
const sel = { cwd: "/x", filePath: "/x/a.md", text: "one\ntwo\nthree", selection: { start: { line: 4 }, end: { line: 6 } } }
assert.equal(banner(sel), "⧉ 3 lines selected")
assert.equal(banner({ cwd: "/x", text: "" }), undefined)
assert.equal(banner(null), undefined)
assert.equal(contextMessage(sel), "The user selected the lines 5 to 7 from /x/a.md:\none\ntwo\nthree")
assert.equal(contextMessage({ cwd: "/x", text: "" }), undefined)
console.log("ok")
