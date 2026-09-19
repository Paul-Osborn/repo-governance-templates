# Migrating V2 repositories to V3

The V3 updater does not rewrite a target repository's V2 history or project source. It adds or
replaces only files listed in the kit manifest whose normalized hash matches a known shipped
version.

## Procedure

1. Commit or otherwise back up the target repository and create a migration branch.
2. Update this kit, then inspect the plan:

   ```sh
   ./update-governance.sh --target /path/to/project --dry-run
   ```

   ```powershell
   .\update-governance.ps1 -Target C:\path\to\project -DryRun
   ```

3. Review `ADD`, `UPGRADE`, and `CONFLICT`. A conflict is preserved and requires deliberate manual
   reconciliation. There is no force-overwrite mode in the V3 updater.
4. Apply the same command without dry-run. Replaced files are copied into a timestamped
   `.governance-backup/` directory. Run it again; the second run should be a no-op.
   Add `.governance-backup/` to an older project's `.gitignore` if it is not already present;
   migration does not overwrite the project-owned ignore file.
5. Manually reconcile project-owned canonical policy. Keep the project purpose/commands/constraints,
   but adopt the concise V3 `AGENTS.md` shape and move rationale to `REPO_RULES.md`.
6. Replace `<owner>` in `.github/CODEOWNERS` and `.github/governance-profile.json`. Configure real
   commands in `scripts/ci/project-checks.sh`.
7. Run `github-governance.sh --repo OWNER/REPO` or the PowerShell equivalent without apply. Review
   plan/capability output, then let the owner apply the settings.
8. Run the full project and governance suites, obtain exact-state independent review, and leave the
   governance PR for the human owner to merge.

## Behavioral changes

- Linux/Omarchy bootstrap/update is native; Windows remains supported.
- Claude PowerShell hooks are no longer installed by default. Existing customized `.claude/` files
  are preserved, but their enforcement is secondary.
- GitHub exact-head review status replaces a project-local Claude receipt as the preferred remote
  gate. The digest receipt remains an explicitly limited fallback.
- CI and remote policy move from optional examples into the installed core.
- Company-specific deployment/hardware instructions are not part of the public core.

If a V2 file is customized, keep it until a human resolves the difference. Advancing
`.governance-version` while a conflict remains would make the migration state misleading, so the
updaters do not do it.
