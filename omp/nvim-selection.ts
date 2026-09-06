// omp extension: follow the live Neovim selection, like Claude Code's /ide.
// nvim (lua/plugins/claude.lua) writes ~/.omp/run/nvim-selection/<cwd>.json on every
// selection change; this reads it on each prompt and attaches the text the way Claude
// does with `selected_lines_in_ide`. Opt-in per session with /ide.
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent"
import * as fs from "fs"
import * as os from "os"
import * as path from "path"

const DIR = path.join(os.homedir(), ".omp", "run", "nvim-selection")

type Sel = {
  cwd: string
  filePath?: string
  text?: string
  selection?: { start: { line: number }; end: { line: number } }
}

function encode(cwd: string): string {
  return cwd.replace(/\//g, "%")
}

// nvim in cwd or any parent of cwd, like Claude's workspaceFolders match.
function read(cwd: string): Sel | null {
  let dir = cwd
  for (;;) {
    try {
      return JSON.parse(fs.readFileSync(path.join(DIR, encode(dir) + ".json"), "utf8"))
    } catch {}
    const parent = path.dirname(dir)
    if (parent === dir) return null
    dir = parent
  }
}

export function banner(sel: Sel | null): string | undefined {
  if (!sel?.text) return undefined
  const n = sel.text.split("\n").length
  return `⧉ ${n} line${n === 1 ? "" : "s"} selected`
}

export function contextMessage(sel: Sel | null): string | undefined {
  if (!sel?.text || !sel.selection) return undefined
  const from = sel.selection.start.line + 1
  const to = sel.selection.end.line + 1
  return `The user selected the lines ${from} to ${to} from ${sel.filePath}:\n${sel.text}`
}

export default async function (pi: ExtensionAPI) {
  let enabled = false
  let ui: ExtensionContext["ui"] | undefined
  let cwd = process.cwd()

  const refresh = () => ui?.setStatus("ide", enabled ? banner(read(cwd)) ?? "⧉ nvim" : undefined)

  pi.on("session_start", async (_e, ctx) => {
    ui = ctx.ui
    cwd = ctx.cwd
    refresh()
  })

  pi.registerCommand("ide", {
    description: "Follow the live Neovim selection (toggle)",
    handler: async (_args, ctx) => {
      ui = ctx.ui
      cwd = ctx.cwd
      if (!enabled && !read(cwd)) {
        ctx.ui.notify("No Neovim bridge for this folder (open nvim here first)", "warning")
        return
      }
      enabled = !enabled
      refresh()
      ctx.ui.notify(enabled ? "Connected to Neovim." : "Disconnected from Neovim.")
    },
  })

  fs.mkdirSync(DIR, { recursive: true })
  fs.watch(DIR, () => refresh())

  pi.on("before_agent_start", async (_e, ctx) => {
    if (!enabled) return
    const content = contextMessage(read(ctx.cwd))
    if (!content) return
    return { message: { customType: "selected_lines_in_ide", content, display: false } }
  })
}
