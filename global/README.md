# Global agent setup (auto-governance for new projects)

These instructions make **any** agent govern a new project automatically: you open an empty
folder, state your task, and the agent scaffolds governance + writes the PRD before coding.

There are two instructions here, and both install the same way:

- [`new-project-bootstrap.md`](new-project-bootstrap.md) - govern a new project automatically.
- [`server-rules.md`](server-rules.md) - the rules for putting anything on Paul's mini PC.
  Added 2026-09-04 after an agent mounted an app on the server's bare address without
  asking and silently displaced what was there, then took four other sites down trying to
  undo it. Every rule in that file is a mistake that has actually happened.

Both are installed into each agent's **global (user-level) config**. Three of the four are
plain files you can write; Cursor's is set in its UI.

| Agent | Where the global instruction goes | How |
|-------|-----------------------------------|-----|
| Claude Code | `C:\Users\<you>\.claude\CLAUDE.md` | Append the bootstrap block. |
| Codex | `C:\Users\<you>\.codex\AGENTS.md` | Create the file with the bootstrap block. |
| Antigravity | `C:\Users\<you>\.gemini\GEMINI.md` | Create the file with the bootstrap block. (Also used by Gemini CLI.) |
| Cursor | Settings → Rules → **User Rules** | Paste `cursor-user-rules.txt` (Cursor stores user rules in-app, not as a file). |
| Grok | **not yet wired up** | `~/.grokbot` holds runtime state only, no instruction file. If Grok reads a project's `AGENTS.md`, the per-project copy covers it; the global rules are NOT reaching it. |

## Notes

- **It activates only after `new-governed-repo.ps1` exists at `$env:REPO_GOVERNANCE_HOME`** —
  i.e. set via `[Environment]::SetEnvironmentVariable('REPO_GOVERNANCE_HOME', '<path to kit>', 'User')`.
- **Safe by design:** the block only fires for a *new* project in a folder with no `AGENTS.md`,
  and the scaffold script skips files that already exist. Existing projects are untouched.
- **Permissions:** the first scaffold in a project may ask the agent's permission to run the
  script — that's the secure default. To make it promptless in Claude Code, add an allow rule
  for the script to `C:\Users\<you>\.claude\settings.json`.
- To change either instruction, edit the file **here** and re-copy to the locations above.
  The installed copies are copies - editing them in place gets undone on the next install.
