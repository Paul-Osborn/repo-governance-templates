# Claude Code adapter

`CLAUDE.md` is a thin import/pointer to canonical `AGENTS.md`. Repo Governance V3 does not install
the V2 PowerShell Claude hooks by default. The legacy templates remain in this kit for existing
Windows projects, but they are optional convenience/defense-in-depth controls and are not the only
enforcement for any critical invariant.

Prefer the cross-agent Lefthook gates and remote controls. If an existing project keeps the V2
Claude hooks, review them as project-specific permission configuration and migrate deliberately;
the V3 updater will not overwrite customized `.claude/settings.json` or hook files.
