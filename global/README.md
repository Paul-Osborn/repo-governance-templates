# Global agent bootstrap

The managed instruction in `new-project-bootstrap.md` teaches an agent to install governance
before product code in a genuinely new folder. It is generic and contains no company deployment
or infrastructure policy.

Install or refresh it without replacing personal instructions:

```sh
./update-global-rules.sh --dry-run
./update-global-rules.sh
```

```powershell
& "$env:REPO_GOVERNANCE_HOME\update-global-rules.ps1" -DryRun
& "$env:REPO_GOVERNANCE_HOME\update-global-rules.ps1"
```

Both updaters replace only the block between the managed markers, create a backup before a write,
and are idempotent. Supported file-backed locations:

| Agent | User-level instruction file |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Claude Code | `~/.claude/CLAUDE.md` |
| Gemini / Antigravity | `~/.gemini/GEMINI.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` |

Cursor stores user rules in its UI; paste `global/cursor-user-rules.txt` manually. Global policy
is a convenience, not a security boundary. The generated repository's hooks and remote controls
remain authoritative.
