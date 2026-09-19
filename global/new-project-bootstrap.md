# Starting a new project — governance before code

Apply this only when the user is creating a new project and the current folder has no `AGENTS.md`.
Never re-scaffold an existing governed project.

Before product code:

1. Locate the Repo Governance kit from `REPO_GOVERNANCE_HOME`. If it is unset, report that instead
   of guessing a path.
2. Scaffold governance with the command for the current platform:

   ```sh
   "$REPO_GOVERNANCE_HOME/new-governed-repo.sh" --target . --name "<project name>"
   ```

   ```powershell
   & "$env:REPO_GOVERNANCE_HOME\new-governed-repo.ps1" -Target . -Name "<project name>"
   ```

3. Establish `PRD.md`: problem, outcome, users, scope/non-goals, constraints, privacy/security,
   success criteria, and important risks. Ask only for missing owner decisions.
4. Fill project-specific placeholders in `AGENTS.md` and `REPO_RULES.md`. Configure
   `scripts/ci/project-checks.sh` with real lint/test/build commands.
5. Branch before the first commit. Commit governance and the brief before product code. Configure
   the remote policy in plan mode before applying it.

Use a bounded `SPEC.md` for substantial work, not for trivial edits. Do not require a cloud service,
Claude Code, Codex, or a heavyweight specification framework to create the repository.
